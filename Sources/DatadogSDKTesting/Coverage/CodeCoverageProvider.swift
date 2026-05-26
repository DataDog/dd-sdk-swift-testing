/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@preconcurrency internal import EventsExporter
internal import CDatadogSDKTesting
@preconcurrency internal import CodeCoverageCollector
@preconcurrency internal import CodeCoverageParser
internal import OpenTelemetryApi
internal import OpenTelemetrySdk

/// SDK-facing collector for code coverage. Mirrors how `TracerSdk` /
/// `LoggerSdk` work: the consumer calls `startCoverage(context:)`,
/// receives a handle (`ActiveCoverage`), and finalises by calling
/// `.end()` on it. The handle ships a `CoverageRecord` to the
/// configured `CoverageProcessor`.
protocol TestCoverageCollector: Feature, Sendable {
    /// Start a coverage-gathering session for the supplied context.
    /// Returns `nil` if gathering couldn't be started.
    func startCoverage(context: CoverageContext) -> ActiveCoverage?
}

/// Live handle returned from `TestCoverageCollector.startCoverage(context:)`.
/// Stop gathering and emit the record to the processor by calling
/// `end()`. `end()` is idempotent.
protocol ActiveCoverage: Sendable {
    var context: CoverageContext { get }
    
    func end()
}

/// One-per-process coverage provider — analogous to `TracerSdk` /
/// `LoggerSdk`. Owns the LLVM coverage gatherer and the
/// `CoverageProcessor` that runs the parsing / upload pipeline.
///
/// `startCoverage(context:)` flips on LLVM gathering and returns an
/// `ActiveCoverage` handle. `ActiveCoverage.end()` snapshots the
/// profraw, builds a `CoverageRecord`, and hands it to the processor —
/// fire-and-forget. All threading lives inside the processor.
final class CodeCoverageProvider: TestCoverageCollector {
    static var id: FeatureId = "CodeCoverageProvider"

    nonisolated(unsafe) let llvmProcessor: LLVMCoverageProcessor
    nonisolated(unsafe) let processor: any CoverageProcessor
    let workspacePath: String?

    let storagePath: Directory
    let debug: Bool

    init(storagePath: Directory, exporter: EventsExporterProtocol,
         workspacePath: String?, priority: CodeCoveragePriority, debug: Bool) throws
    {
        let llvm = try LLVMCoverageProcessor(for: PlatformUtils.xcodeVersion,
                                             temp: storagePath.url)
        self.llvmProcessor = llvm
        self.processor = BackgroundCoverageProcessor(exporter: exporter,
                                                     parser: llvm.parser,
                                                     priority: priority,
                                                     cleanupCoverageFiles: !debug)
        self.debug = debug
        self.storagePath = storagePath
        self.workspacePath = workspacePath
        setFileLimit()
    }

    func startCoverage(context: CoverageContext) -> ActiveCoverage? {
        do {
            try llvmProcessor.startCoverageGathering()
        } catch {
            Log.debug("Can't start coverage gathering, error: \(error)")
            return nil
        }
        return Active(provider: self, context: context)
    }

    /// Stop LLVM gathering, build a `CoverageRecord` for the given context,
    /// and hand it to the processor. Called from `Active.end()` only.
    fileprivate func finishCoverage(context: CoverageContext) {
        let file: URL
        do {
            file = try llvmProcessor.stopCoverageGathering()
        } catch {
            Log.debug("Coverage gathering error: \(error)")
            return
        }
        let record = CoverageRecord(
            name: file.deletingPathExtension().lastPathComponent.components(separatedBy: "__").last ?? file.lastPathComponent,
            coverageFileURL: file,
            workspacePath: workspacePath.map { URL(fileURLWithPath: $0) },
            resource: Resource(),
            instrumentationScopeInfo: InstrumentationScopeInfo(),
            context: context
        )
        processor.onEnd(record: record)
    }

    private final class Active: ActiveCoverage {
        // The provider outlives the per-test handles; a weak ref keeps a
        // leaked `Active` from pinning the SDK alive.
        weak var provider: CodeCoverageProvider?
        let context: CoverageContext
        // Ensures `end()` runs at most once even if both the caller and a
        // safety net (e.g. deinit fallback) invoke it.
        private let _ended = Synced(false)

        init(provider: CodeCoverageProvider, context: CoverageContext) {
            self.provider = provider
            self.context = context
        }

        func end() {
            let wasEnded: Bool = _ended.update { value in
                let was = value
                value = true
                return was
            }
            guard !wasEnded else { return }
            provider?.finishCoverage(context: context)
        }
    }

    private func setFileLimit() {
        var limit = rlimit()
        let filesMax = 4096
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else {
            Log.debug("Can't get open file limit")
            return
        }
        let curLimit = limit.rlim_cur
        guard curLimit < filesMax else {
            Log.debug("Open file limit is good: \(curLimit)")
            return
        }
        limit.rlim_cur = rlim_t(filesMax)
        if setrlimit(RLIMIT_NOFILE, &limit) == 0 {
            Log.debug("Updated open file limit to \(filesMax) from \(curLimit)")
        } else {
            Log.debug("Can't increase open file limit")
        }
    }

    deinit {
        if !debug {
            try? storagePath.delete()
        } else {
            Log.debug("CodeCoverageProvider storage path: \(storagePath.url.path)")
        }
    }

    func removeStoragePath() {
        try? storagePath.delete()
    }

    func stop() {
        // Drain the processor's queued parse + upload work and flush the
        // exporter; multithreading lives inside the processor now.
        _ = processor.forceFlush()
    }

    fileprivate static func generateProfData(profrawFile: URL) -> URL? {
        let outputURL = profrawFile.deletingPathExtension().appendingPathExtension("profdata")
        let input = profrawFile.path
        let outputPath = outputURL.path
        let commandToRun = #"xcrun llvm-profdata merge -sparse "\#(input)" -o "\#(outputPath)""#
        guard let llvmProfDataOutput = Spawn.combined(try: commandToRun, log: Log.instance) else {
            return nil
        }
        Log.debug("llvm-profdata output: \(llvmProfDataOutput)")
        return outputURL
    }

    static func getModuleCoverage(profrawFile: URL, binaryImagePaths: [String]) -> LLVMTotalsCoverageFormat? {
        guard let profDataURL = generateProfData(profrawFile: profrawFile) else {
            return nil
        }
        let covJsonURL = profDataURL
            .deletingLastPathComponent()
            .appendingPathComponent("TotalCoverage.json", isDirectory: false)
        let binariesPath = binaryImagePaths.map { #""\#($0)""# }.joined(separator: " -object ")
        let commandToRun = #"xcrun llvm-cov export -instr-profile "\#(profDataURL.path)" \#(binariesPath) > "\#(covJsonURL.path)""#
        guard let llvmCovOutput = Spawn.combined(try: commandToRun, log: Log.instance) else {
            return nil
        }
        Log.debug("llvm-cov output: \(llvmCovOutput)")
        defer { try? FileManager.default.removeItem(at: covJsonURL) }
        return LLVMTotalsCoverageFormat(fromURL: covJsonURL)
    }

    static func getLineCodeCoverage() -> Double? {
        // Check do we have profiling enabled
        guard let llvmProfilePath = try? CoverageCollector.currentCoverageFile,
              llvmProfilePath != "/dev/null" else { return nil }
        let binaries = CoveredBinary.currentProcessBinaries
        // if not continuous mode then save all data
        if !llvmProfilePath.contains(exactWord: "%c") {
            // Save all profiling data
            binaries.writeCoverage()
        }
        // Locate profraw file
        guard let llvmProfileUrl = CoverageParser.initialCoverageFileURL(coverageFilePath: llvmProfilePath) else {
            return nil
        }
        // Get total coverage
        let coverage = getModuleCoverage(profrawFile: llvmProfileUrl,
                                         binaryImagePaths: binaries.map { $0.path })
        return coverage?.data.first?.totals.lines.percent
    }
}
