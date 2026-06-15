/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

/// Public surface of the coverage exporter — accepts the fully-parsed
/// `CoverageData` payloads produced by a `CoverageProcessor` and writes
/// them to disk + uploads them to the backend. The URL-stage entry
/// point lives on `CoverageProcessor.onEnd(record:)`.
public protocol CoverageExporterType {
    @discardableResult
    func export(coverageData: [CoverageData], explicitTimeout: TimeInterval?) -> ExportResult
    @discardableResult
    func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult
    func shutdown(explicitTimeout: TimeInterval?)
}

public extension CoverageExporterType {
    @discardableResult
    func export(coverageData: [CoverageData]) -> ExportResult {
        export(coverageData: coverageData, explicitTimeout: nil)
    }

    @discardableResult
    func forceFlush() -> ExportResult { forceFlush(explicitTimeout: nil) }

    func shutdown() { shutdown(explicitTimeout: nil) }
}

internal final class CoverageExporter: CoverageExporterType {
    let configuration: ExporterConfiguration
    let coverageStorage: FeatureStoreAndUpload
    private let payloadObserver: PayloadObserver?

    init(config: ExporterConfiguration, storage: Directory, api: TestImpactAnalysisApi,
         observers: ExporterObservers.Feature = .init()) throws {
        self.configuration = config

        let uploadObserver = observers.upload
        let filesOrchestrator = FilesOrchestrator(
            directory: try storage.createSubdirectory(path: "v1"),
            performance: PerformancePreset.instantDataDelivery,
            dateProvider: SystemDateProvider(),
            onDrop: uploadObserver.map { obs in { obs.uploadDropped(payloadBytes: $0) } }
        )

        let encoder = api.encoder
        let dataFormat = try DataFormat(header: Header(), encoder: encoder)

        let writer = FileWriter(entity: "coverage",
                                dataFormat: dataFormat,
                                orchestrator: filesOrchestrator,
                                encoder: encoder,
                                observer: observers.payload)
        let reader = FileReader(dataFormat: dataFormat, orchestrator: filesOrchestrator)
        let requestObserver = observers.request
        let upload: ClosureDataUploader.UploadCallback = { (data: Data) async throws(APICallError) -> Void in
            try await api.uploadCoverage(batch: data, observer: requestObserver)
        }
        let uploader = ClosureDataUploader(upload: upload)
        self.payloadObserver = observers.payload
        self.coverageStorage = FeatureStoreAndUpload(featureName: "coverage",
                                                     reader: reader,
                                                     writer: writer,
                                                     performance: configuration.performancePreset,
                                                     uploader: uploader,
                                                     log: configuration.logger,
                                                     observer: observers.upload)
    }

    @discardableResult
    func export(coverageData: [CoverageData], explicitTimeout: TimeInterval?) -> ExportResult {
        for record in coverageData {
            let coverage = TestCodeCoverage(sessionId: record.context.sessionId.rawValue,
                                            suiteId: record.context.suiteId.rawValue,
                                            spanId: record.context.testId?.rawValue ?? 0,
                                            workspace: record.workspacePath?.path,
                                            files: record.files)
            writeCoverage(coverage)
        }
        return .success
    }

    @discardableResult
    func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult {
        (try? coverageStorage.flush()) == true ? .success : .failure
    }

    func shutdown(explicitTimeout: TimeInterval?) {
        coverageStorage.stop()
    }

    private func writeCoverage(_ data: TestCodeCoverage) {
        payloadObserver?.eventEnqueued()
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
