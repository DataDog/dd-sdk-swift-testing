/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@preconcurrency internal import CodeCoverageParser
@preconcurrency internal import EventsExporter
internal import OpenTelemetrySdk

/// Concrete `CoverageProcessor` that runs parsing + upload off the test
/// thread. On `onEnd(record:)` it enqueues parsing of the profraw the
/// record points to on its own `OperationQueue` (one per process,
/// configurable QoS), converts per-file coverage segments into a
/// bit-per-line bitmap, and hands the resulting `CoverageData` to a
/// `CoverageExporterType`.
///
/// All multithreading lives here so callers (`CodeCoverageProvider`)
/// can stay synchronous and treat `onEnd(record:)` as fire-and-forget.
/// `forceFlush` / `shutdown` drain the queue before forwarding to the
/// exporter.
///
/// Lives in `DatadogSDKTesting` rather than `EventsExporter` so the
/// exporter module stays decoupled from `CodeCoverageParser`.
final class BackgroundCoverageProcessor: CoverageProcessor {
    private let exporter: any CoverageExporterType
    private let parser: CoverageParser
    private let workQueue: OperationQueue
    private let cleanupCoverageFiles: Bool

    init(exporter: any CoverageExporterType,
         parser: CoverageParser,
         priority: CodeCoveragePriority,
         cleanupCoverageFiles: Bool = true)
    {
        self.exporter = exporter
        self.parser = parser
        self.cleanupCoverageFiles = cleanupCoverageFiles
        let queue = OperationQueue()
        queue.qualityOfService = priority.qos
        queue.maxConcurrentOperationCount = max(ProcessInfo.processInfo.activeProcessorCount - 1, 1)
        self.workQueue = queue
    }

    func onEnd(record: CoverageRecord) {
        let parser = self.parser
        let exporter = self.exporter
        let cleanup = self.cleanupCoverageFiles
        workQueue.addOperation {
            guard FileManager.default.fileExists(atPath: record.coverageFileURL.path) else {
                Log.debug("Coverage file is missing at: \(record.coverageFileURL.path)")
                return
            }
            Log.debug("Start processing coverage: \(record.coverageFileURL.path)")
            defer {
                if cleanup {
                    try? FileManager.default.removeItem(at: record.coverageFileURL)
                }
            }

            let info: CoverageInfo
            do {
                info = try parser.filesCovered(in: record.coverageFileURL)
            } catch {
                Log.print("Coverage parsing failed for \(record.name): \(error)")
                return
            }
            let files = info.files.values.map { CoverageFile(file: $0) }
            let data = CoverageData(name: record.name,
                                    files: files,
                                    workspacePath: record.workspacePath,
                                    resource: record.resource,
                                    instrumentationScopeInfo: record.instrumentationScopeInfo,
                                    context: record.context)
            _ = exporter.export(coverageData: [data], explicitTimeout: nil)
            Log.debug("End processing coverage: \(record.coverageFileURL.path)")
        }
    }

    @discardableResult
    func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult {
        drainSynchronously()
        return exporter.forceFlush(explicitTimeout: explicitTimeout)
    }

    func shutdown(explicitTimeout: TimeInterval?) {
        drainSynchronously()
        exporter.shutdown(explicitTimeout: explicitTimeout)
    }

    /// Block until every queued parse + upload has finished. We bump the
    /// queue's QoS and concurrency for the duration of the drain so we
    /// don't hold up shutdown waiting on a low-priority background queue.
    private func drainSynchronously() {
        let oldQos = workQueue.qualityOfService
        let oldConcurrency = workQueue.maxConcurrentOperationCount
        workQueue.maxConcurrentOperationCount = ProcessInfo.processInfo.activeProcessorCount
        workQueue.qualityOfService = .userInteractive
        workQueue.waitUntilAllOperationsAreFinished()
        workQueue.qualityOfService = oldQos
        workQueue.maxConcurrentOperationCount = oldConcurrency
    }
}

// MARK: - CoverageInfo.File → CoverageFile bitmap

extension CoverageFile {
    /// Build a bit-per-line coverage bitmap from a `CoverageInfo.File`.
    /// One bit per source line; line N (1-based) sets bit `7 - ((N-1) % 8)`
    /// in byte `(N-1) / 8`. Workspace stripping is done by
    /// `TestCodeCoverage` on the exporter side.
    init(file: CoverageInfo.File) {
        let coveredLines = file.coveredLines
        guard let lastLine = coveredLines.last else {
            self.init(name: file.name, bitmap: Data())
            return
        }
        let byteCount = lastLine % 8 == 0 ? lastLine / 8 : lastLine / 8 + 1
        var bitmap = Data(repeating: 0, count: byteCount)
        bitmap.withUnsafeMutableBytes { bytes in
            for line in coveredLines {
                let line0 = line - 1
                let index = line0 / 8
                let byte = bytes[index]
                bytes[index] = byte | (1 << (7 - (line0 % 8)))
            }
        }
        self.init(name: file.name, bitmap: bitmap)
    }
}

extension CoverageInfo.File {
    /// 1-based line numbers covered by at least one segment in this file.
    var coveredLines: IndexSet {
        var indexes = IndexSet()
        for location in segments.keys {
            indexes.insert(integersIn: Int(location.startLine)...Int(location.endLine))
        }
        return indexes
    }
}
