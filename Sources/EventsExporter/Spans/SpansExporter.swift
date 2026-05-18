/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

internal final class SpansExporter {
    let spansDirectory = "com.datadog.civisibility/spans/v1"
    let configuration: ExporterConfiguration
    let spansStorage: FeatureStoreAndUpload
    let runtimeId: String

    init(config: ExporterConfiguration, api: SpansApi) throws {
        self.configuration = config

        let filesOrchestrator = FilesOrchestrator(
            directory: try Directory(withSubdirectoryPath: spansDirectory),
            performance: configuration.performancePreset,
            dateProvider: SystemDateProvider()
        )

        var metadata = config.metadata
        self.runtimeId = metadata[string: "runtime-id"] ?? UUID().uuidString.lowercased()
        metadata[string: "runtime-id"] = self.runtimeId

        let encoder = api.encoder
        let dataFormat = try DataFormat(header: Header(metadata: metadata.metadata),
                                        encoder: encoder)

        let writer = FileWriter(entity: "spans",
                                dataFormat: dataFormat,
                                orchestrator: filesOrchestrator,
                                encoder: encoder)
        let reader = FileReader(dataFormat: dataFormat, orchestrator: filesOrchestrator)
        let upload: ClosureDataUploader.UploadCallback = { (data: Data) async throws(HTTPClient.RequestError) -> Void in
            try await api.uploadSpans(batch: data)
        }
        let uploader = ClosureDataUploader(upload: upload)
        self.spansStorage = FeatureStoreAndUpload(featureName: "spans",
                                                  reader: reader,
                                                  writer: writer,
                                                  performance: configuration.performancePreset,
                                                  uploader: uploader)
    }

    func exportSpan(span: SpanData) {
        if span.attributes["type"]?.description == "test" {
            let envelope = CITestEnvelope(DDSpan(spanData: span,
                                                 serviceName: configuration.serviceName,
                                                 applicationVersion: configuration.version))
            write(envelope)
        } else {
            let envelope = SpanEnvelope(DDSpan(spanData: span,
                                               serviceName: configuration.serviceName,
                                               applicationVersion: configuration.version))
            write(envelope)
        }
    }

    func shutdown() {
        spansStorage.stop()
    }

    private func write<T: Encodable>(_ value: T) {
        if configuration.performancePreset.synchronousWrite {
            try? spansStorage.writeSync(value: value)
        } else {
            spansStorage.write(value: value)
        }
    }
}

extension SpansExporter {
    struct Header: JSONFileHeader {
        let version: Int = 1
        let metadata: [String: [String: SpanMetadata.Value]]
        static var batchFieldName: String { "events" }
    }
}
