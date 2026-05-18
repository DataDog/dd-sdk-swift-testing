/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import CodeCoverageParser

/// A single per-test or per-suite coverage payload. The caller (DDCoverageHelper)
/// parses the raw profraw file and builds a record with the OTel anchors
/// (`Resource`, `InstrumentationScopeInfo`, span context) — coverage upload
/// happens through `CoverageExporterType.export(coverageRecords:)`. Not Codable:
/// the on-wire shape is `TestCodeCoverage`, built inside the exporter.
public struct CoverageRecord {
    public enum Context {
        case test(testSpanId: SpanId, suiteId: SpanId, sessionId: SpanId)
        case suite(suiteSpanId: SpanId, sessionId: SpanId)

        public var sessionId: SpanId {
            switch self {
            case .test(_, _, let id), .suite(_, let id): return id
            }
        }

        public var suiteId: SpanId {
            switch self {
            case .test(_, let id, _): return id
            case .suite(let id, _): return id
            }
        }

        public var testId: SpanId? {
            switch self {
            case .test(let id, _, _): return id
            case .suite: return nil
            }
        }

        public var isSuite: Bool {
            if case .suite = self { return true }
            return false
        }
    }

    public let name: String
    public let coverage: CoverageInfo
    public let resource: Resource
    public let instrumentationScopeInfo: InstrumentationScopeInfo
    public let context: Context
    public let workspacePath: URL?

    public init(name: String,
                coverage: CoverageInfo,
                workspacePath: URL?,
                resource: Resource,
                instrumentationScopeInfo: InstrumentationScopeInfo,
                context: Context)
    {
        self.name = name
        self.coverage = coverage
        self.workspacePath = workspacePath
        self.resource = resource
        self.instrumentationScopeInfo = instrumentationScopeInfo
        self.context = context
    }
}

/// Public surface of the coverage feature's exporter — record-based,
/// drives the per-test profraw → TestCodeCoverage pipeline.
public protocol CoverageExporterType {
    func export(coverageRecords: [CoverageRecord], explicitTimeout: TimeInterval?) -> ExportResult
    func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult
    func shutdown(explicitTimeout: TimeInterval?)
}

public extension CoverageExporterType {
    @discardableResult
    func export(coverageRecords: [CoverageRecord]) -> ExportResult {
        export(coverageRecords: coverageRecords, explicitTimeout: nil)
    }

    @discardableResult
    func forceFlush() -> ExportResult { forceFlush(explicitTimeout: nil) }

    func shutdown() { shutdown(explicitTimeout: nil) }
}

internal final class CoverageExporter: CoverageExporterType {
    let coverageDirectory = "com.datadog.civisibility/coverage/v1"
    let configuration: ExporterConfiguration
    let coverageStorage: FeatureStoreAndUpload

    init(config: ExporterConfiguration, api: TestImpactAnalysisApi) throws {
        self.configuration = config

        let filesOrchestrator = FilesOrchestrator(
            directory: try Directory(withSubdirectoryPath: coverageDirectory),
            performance: PerformancePreset.instantDataDelivery,
            dateProvider: SystemDateProvider()
        )

        let encoder = api.encoder
        let dataFormat = try DataFormat(header: Header(), encoder: encoder)

        let writer = FileWriter(entity: "coverage",
                                dataFormat: dataFormat,
                                orchestrator: filesOrchestrator,
                                encoder: encoder)
        let reader = FileReader(dataFormat: dataFormat, orchestrator: filesOrchestrator)
        let upload: ClosureDataUploader.UploadCallback = { (data: Data) async throws(HTTPClient.RequestError) -> Void in
            try await api.uploadCoverage(batch: data)
        }
        let uploader = ClosureDataUploader(upload: upload)
        self.coverageStorage = FeatureStoreAndUpload(featureName: "coverage",
                                                     reader: reader,
                                                     writer: writer,
                                                     performance: configuration.performancePreset,
                                                     uploader: uploader)
    }

    func export(coverageRecords: [CoverageRecord], explicitTimeout: TimeInterval?) -> ExportResult {
        for record in coverageRecords {
            let coverage = TestCodeCoverage(sessionId: record.context.sessionId.rawValue,
                                            suiteId: record.context.suiteId.rawValue,
                                            spanId: record.context.testId?.rawValue ?? 0,
                                            workspace: record.workspacePath?.path,
                                            files: record.coverage.files.values)
            writeCoverage(coverage)
        }
        return .success
    }

    func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult {
        (try? coverageStorage.flush()) == true ? .success : .failure
    }

    func shutdown(explicitTimeout: TimeInterval?) {
        coverageStorage.stop()
    }

    private func writeCoverage(_ data: TestCodeCoverage) {
        if configuration.performancePreset.synchronousWrite {
            try? coverageStorage.writeSync(value: data)
        } else {
            coverageStorage.write(value: data)
        }
    }
}

extension CoverageExporter {
    struct Header: JSONFileHeader {
        let version: Int = 2
        static var batchFieldName: String { "coverages" }
    }
}
