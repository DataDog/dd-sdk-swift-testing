/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import CodeCoverageParser

public protocol CoverageExporterType {
    func export(coverageRecords: [CoverageRecord], explicitTimeout: TimeInterval?) -> ExportResult

    /// Shutdown the log exporter
    ///
    func shutdown(explicitTimeout: TimeInterval?)

    /// Processes all the log records that have not yet been processed
    ///
    func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult
}

public struct CoverageRecord: Codable {
    public enum Context: Codable {
        case test(span: SpanContext, suiteId: SpanId, sessionId: SpanId)
        case suite(span: SpanContext, sessionId: SpanId)
        
        var suiteId: SpanId {
            switch self {
            case .suite(span: let span, sessionId: _): return span.spanId
            case .test(span: _, suiteId: let id, sessionId: _): return id
            }
        }
        
        var sessionId: SpanId {
            switch self {
            case .suite(span: _, sessionId: let id): return id
            case .test(span: _, suiteId: _, sessionId: let id): return id
            }
        }
        
        var testId: SpanId? {
            switch self {
            case .suite: return nil
            case .test(span: let span, suiteId: _, sessionId: _): return span.spanId
            }
        }
        
        var iSuite: Bool {
            switch self {
            case .suite: return true
            case .test: return false
            }
        }
    }
    
    public init(name: String,
                coverage: CoverageInfo,
                workspacePath: URL?,
                resource: Resource,
                instrumentationScopeInfo: InstrumentationScopeInfo,
                context: Context)
    {
        self.name = name
        self.resource = resource
        self.instrumentationScopeInfo = instrumentationScopeInfo
        self.context = context
        self.coverage = coverage
        self.workspacePath = workspacePath
    }
    
    public let name: String
    public let coverage: CoverageInfo
    public let resource: Resource
    public let instrumentationScopeInfo: InstrumentationScopeInfo
    public let context: Context
    public let workspacePath: URL?
}

internal class CoverageExporter: CoverageExporterType {
    let coverageDirectory = "com.datadog.testoptimization/coverage/v1"
    let configuration: ExporterConfiguration
    let coverageStorage: FeatureStoreAndUpload
    let log: Logger

    init(config: ExporterConfiguration, api: TestImpactAnalysisApi) throws {
        self.configuration = config
        self.log = config.logger
        
        let filesOrchestrator = try FilesOrchestrator(
            directory: try Directory.cache().createSubdirectory(path: coverageDirectory),
            performance: configuration.performancePreset,
            dateProvider: SystemDateProvider()
        )
        
        let dataFormat = try DataFormat(header: Header(), encoder: api.encoder)

        let coverageFileWriter = FileWriter(
            entity: "coverage",
            dataFormat: dataFormat,
            orchestrator: filesOrchestrator,
            encoder: api.encoder
        )

        let coverageFileReader = FileReader(
            dataFormat: dataFormat,
            orchestrator: filesOrchestrator
        )
        
        let uploader = ClosureDataUploader { data in
            api.uploadCoverage(batch: data)
        }

        coverageStorage = .init(featureName: "coverage",
                                reader: coverageFileReader,
                                writer: coverageFileWriter,
                                performance: config.performancePreset,
                                uploader: uploader)
    }
    
    func export(coverageRecords: [CoverageRecord], explicitTimeout: TimeInterval?) -> ExportResult {
        coverageRecords.forEach {
            let coverage = TestCodeCoverage(sessionId: $0.context.sessionId.rawValue,
                                            suiteId: $0.context.suiteId.rawValue,
                                            spanId: $0.context.testId?.rawValue,
                                            workspace: $0.workspacePath?.path,
                                            files: $0.coverage.files.values)
            _writeCoverage(coverage)
            if let url = configuration.debugSaveCodeCoverageFilesAt, let data = try? JSONEncoder.apiEncoder.encode(coverage) {
                let file = url.appendingPathComponent($0.name + ".json", isDirectory: false)
                try? data.write(to: file)
            }
        }
        return .success
    }

    func export(coverage: URL, parser: CoverageParser, workspacePath: String?,
                testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64)
    {
        log.debug("Start processing coverage: \(coverage.path)")
        var coverageData: TestCodeCoverage? = nil
        
        defer {
            if configuration.debugSaveCodeCoverageFiles {
                if let coverageData = coverageData, let data = try? JSONEncoder.apiEncoder.encode(coverageData) {
                    let testName = coverage.deletingPathExtension().lastPathComponent.components(separatedBy: "__").last!
                    let jsonURL = coverage.deletingLastPathComponent()
                        .appendingPathComponent(testName + ".json", isDirectory: false)
                    try? data.write(to: jsonURL)
                }
            } else {
                try? FileManager.default.removeItem(at: coverage)
            }
        }
        
        do {
            let info = try parser.filesCovered(in: coverage)
            coverageData = TestCodeCoverage(sessionId: testSessionId,
                                            suiteId: testSuiteId,
                                            spanId: spanId,
                                            workspace: workspacePath,
                                            files: info.files.values)
            try coverageStorage.writer.writeSync(value: coverageData!)
        } catch {
            log.print("Code coverage generation failed: \(error)")
            return
        }
        
        log.debug("End processing coverage: \(coverage.path)")
    }
    
    func flush() -> SpanExporterResultCode {
        do {
            return try coverageStorage.flush() ? .success : .failure
        } catch {
            log.print("Coverage flush failed: \(error)")
            return .failure
        }
    }
    
    private func _writeCoverage(_ data: TestCodeCoverage) {
        if configuration.performancePreset.synchronousWrite {
            try? coverageStorage.writeSync(value: data)
        } else {
            _ = coverageStorage.write(value: data)
        }
    }
}

private extension CoverageExporter {
    struct Header: JSONFileHeader {
        let version: String = "2"
        static var batchFieldName: String { "coverages" }
    }
}

extension TestCodeCoverage.File {
    init(info: CoverageInfo.File, workspace: String?) {
        var coveredLines = IndexSet()
        for location in info.segments.keys {
            coveredLines.insert(integersIn: Int(location.startLine)...Int(location.endLine))
        }
        self.init(name: info.name, workspace: workspace, lines: coveredLines)
    }
}

extension TestCodeCoverage {
    init(sessionId: UInt64, suiteId: UInt64, spanId: UInt64?, workspace: String?, files: Dictionary<String, CoverageInfo.File>.Values) {
        self.sessionId = sessionId
        self.suiteId = suiteId
        self.spanId = spanId
        let workspacePath = workspace.map { $0.last == "/" ? $0 : $0 + "/" }
        self.files = files.map { File(info: $0, workspace: workspacePath) }
    }
}
