//
//  CoverageExporter.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 03/12/2025.
//

import Foundation
internal import CodeCoverageCollector
internal import CodeCoverageParser
internal import OpenTelemetryApi
internal import OpenTelemetrySdk
internal import EventsExporter

struct Coverage {
    let coverageFile: URL
    let name: String
    let resource: Resource
    let instrumentationScopeInfo: InstrumentationScopeInfo
    let context: CoverageRecord.Context
}

protocol CoverageCollector: AnyObject {
    func stopCollectingAndEmit() throws
}

protocol CoverageProcessor: AnyObject {
    /// Called when a Logger's CoverageCollector emits a coverage record
    ///
    /// - Parameter coverage: the coverage file emitted
    func onEmit(coverage: Coverage)
    
    /// Called when CoverageCollector.shutdown() is called.
    /// Implementations must ensure that all span events are processed before returning
    func shutdown(explicitTimeout: TimeInterval?)

    /// Processes all coverage events that have not yet been processed.
    /// This method is executed synchronously on the calling thread
    /// - Parameter timeout: Maximum time the flush complete or abort. If nil, it will wait indefinitely
    func forceFlush(timeout: TimeInterval?)
}

protocol CoverageCollectorBuilder {
    func startCollecting() throws -> any CoverageCollector
    func withCollectedCoverage<T>(_ body: () throws -> T) throws -> T
}

extension CoverageCollectorBuilder {
    func withCollectedCoverage<T>(_ body: () throws -> T) throws -> T {
        var coverage = try startCollecting()
        let value: T
        do {
            value = try body()
        } catch {
            try coverage.stopCollectingAndEmit()
            throw error
        }
        try coverage.stopCollectingAndEmit()
        return value
    }
}

final class LLVMCoverageCollector: CoverageCollector {
    private var isCollecting: Bool
    private let collector: CodeCoverageCollector.CoverageCollector
    private let processor: CoverageProcessor
    private let resource: Resource
    private let name: String
    private let instrumentationScopeInfo: InstrumentationScopeInfo
    private let context: CoverageRecord.Context
    
    init(name: String,
         resource: Resource,
         instrumentationScopeInfo: InstrumentationScopeInfo,
         context: CoverageRecord.Context,
         collector: CodeCoverageCollector.CoverageCollector,
         processor: CoverageProcessor)
    {
        self.isCollecting = true
        self.name = name
        self.collector = collector
        self.processor = processor
        self.resource = resource
        self.context = context
        self.instrumentationScopeInfo = instrumentationScopeInfo
    }
    
    func stopCollectingAndEmit() throws {
        guard isCollecting else { return }
        isCollecting = false
        
        let file = try collector.stopCoverageGathering()
        processor.onEmit(coverage: .init(coverageFile: file,
                                         name: name,
                                         resource: resource,
                                         instrumentationScopeInfo: instrumentationScopeInfo,
                                         context: context))
    }
}

final class LLVMCoverageCollectorBuilder: CoverageCollectorBuilder {
    private let collector: CodeCoverageCollector.CoverageCollector
    private let processor: CoverageProcessor
    private let resource: Resource
    
    init(collector: CodeCoverageCollector.CoverageCollector,
         processor: CoverageProcessor,
         resource: Resource)
    {
        self.collector = collector
        self.processor = processor
        self.resource = resource
    }
    
    func startCollecting() throws -> any CoverageCollector {
        guard let span = OpenTelemetry.instance.contextProvider.activeSpan as? ReadableSpan else {
            
        }
        let attrs = span.getAttributes()
        guard let sessionId = attrs.testSessionId else {
            
        }
        let context: CoverageRecord.Context
        if let suiteId = attrs.testSuiteId {
            context = .test(span: span.context, suiteId: suiteId, sessionId: sessionId)
        } else {
            context = .suite(span: span.context, sessionId: sessionId)
        }
        return LLVMCoverageCollector(name: span.name,
                                     resource: resource,
                                     instrumentationScopeInfo: span.instrumentationScopeInfo,
                                     context: context,
                                     collector: collector,
                                     processor: processor)
    }
}

final class LLVMCoverageProcessor: CoverageProcessor {
    let operationQueue: OperationQueue
    let parser: CoverageParser
    let exporter: CoverageExporterType
    let workspacePath: URL?
    let debug: Bool
    var onError: (any Error) -> Void
    private(set) var isShutdown: Bool = false
    
    init(exporter: CoverageExporterType, parser: CoverageParser,
         workspacePath: URL?, priority: CodeCoveragePriority,
         onError: @escaping (any Error) -> Void = {_ in},
         debug: Bool) throws
    {
        self.parser = parser
        self.exporter = exporter
        self.onError = onError
        self.workspacePath = workspacePath
        self.operationQueue = OperationQueue()
        self.operationQueue.qualityOfService = priority.qos
        self.operationQueue.maxConcurrentOperationCount = max(ProcessInfo.processInfo.activeProcessorCount - 1, 1)
        self.debug = debug
        
        setFileLimit()
    }
    
    func onEmit(coverage: Coverage) {
        guard !isShutdown else { return }
        operationQueue.addOperation {
            do {
                let info = try self.parser.filesCovered(in: coverage.coverageFile)
                let record = CoverageRecord(name: coverage.name,
                                            coverage: info,
                                            workspacePath: self.workspacePath,
                                            resource: coverage.resource,
                                            instrumentationScopeInfo: coverage.instrumentationScopeInfo,
                                            context: coverage.context)
                let _ = self.exporter.export(coverageRecords: [record], explicitTimeout: nil)
            } catch {
                self.onError(error)
            }
            if !self.debug {
                try? FileManager.default.removeItem(at: coverage.coverageFile)
            }
        }
    }
    
    func shutdown(explicitTimeout: TimeInterval?) {
        guard !isShutdown else { return }
        isShutdown = true
        operationQueue.qualityOfService = .userInteractive
        forceFlush(timeout: explicitTimeout)
        exporter.shutdown(explicitTimeout: explicitTimeout)
    }

    /// Processes all coverage events that have not yet been processed.
    /// This method is executed synchronously on the calling thread
    /// - Parameter timeout: Maximum time the flush complete or abort. If nil, it will wait indefinitely
    func forceFlush(timeout: TimeInterval?) {
        self.operationQueue.waitUntilAllOperationsAreFinished()
        self.operationQueue.addOperation {
            let _ = self.exporter.forceFlush(explicitTimeout: timeout)
        }
        self.operationQueue.waitUntilAllOperationsAreFinished()
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
}
