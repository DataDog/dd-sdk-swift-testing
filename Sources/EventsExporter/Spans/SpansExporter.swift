/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

internal final class SpansExporter: SpanExporter {
    let configuration: ExporterConfiguration
    let runtimeId: String
    let spansStorage: FeatureStoreAndUpload
    private let encoder: JSONEncoder

    init(config: ExporterConfiguration, storage: Directory, api: SpansApi,
         observers: ExporterObservers.Feature = .init()) throws {
        self.configuration = config

        let filesOrchestrator = FilesOrchestrator(
            directory: try storage.createSubdirectory(path: "v1"),
            performance: configuration.performancePreset,
            dateProvider: SystemDateProvider()
        )

        var metadata = SpanSanitizer().sanitize(metadata: config.metadata)
        self.runtimeId = metadata[string: "runtime-id"] ?? UUID().uuidString.lowercased()
        metadata[string: "runtime-id"] = self.runtimeId

        let encoder = api.encoder
        self.encoder = encoder
        let dataFormat = try DataFormat(header: Header(metadata: metadata.metadata),
                                        encoder: encoder)

        let writer = FileWriter(entity: "spans",
                                dataFormat: dataFormat,
                                orchestrator: filesOrchestrator,
                                encoder: encoder,
                                observer: observers.payload)
        let reader = FileReader(dataFormat: dataFormat, orchestrator: filesOrchestrator)
        let requestObserver = observers.request
        let upload: ClosureDataUploader.UploadCallback = { (data: Data) async throws(APICallError) -> Void in
            try await api.uploadSpans(batch: data, observer: requestObserver)
        }
        let uploader = ClosureDataUploader(upload: upload)
        self.spansStorage = FeatureStoreAndUpload(featureName: "spans",
                                                  reader: reader,
                                                  writer: writer,
                                                  performance: configuration.performancePreset,
                                                  uploader: uploader,
                                                  observer: observers.upload)
    }

    /// Rebuild the file header (which embeds the per-feature `SpanMetadata`)
    /// and rotate the writable file so the new header takes effect on the
    /// next batch. The runtime-id stays pinned across updates.
    func setMetadata(_ meta: SpanMetadata) {
        var meta = SpanSanitizer().sanitize(metadata: meta)
        meta[string: "runtime-id"] = self.runtimeId
        // `try!` is safe: `Header` is a fixed-shape struct that always encodes.
        let dataFormat = try! DataFormat(header: Header(metadata: meta.metadata),
                                         encoder: encoder)
        spansStorage.update(dataFormat: dataFormat)
    }

    func exportSpan(span: SpanData) {
        if let typeStr = span.attributes.type,
           let type = TestSpan.SpanType(rawValue: typeStr)
        {
            write(TestSpanEnvelope(TestSpan(spanData: span, spanType: type)))
        } else {
            write(SpanEnvelope(DDSpan(spanData: span)))
        }
    }

    private func write<T: Encodable>(_ value: T) {
        if configuration.performancePreset.synchronousWrite {
            try? spansStorage.writeSync(value: value)
        } else {
            spansStorage.write(value: value)
        }
    }

    // MARK: - OpenTelemetrySdk.SpanExporter

    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        for span in spans {
            exportSpan(span: span)
        }
        return .success
    }

    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        (try? spansStorage.flush()) == true ? .success : .failure
    }

    func shutdown(explicitTimeout: TimeInterval?) {
        spansStorage.stop()
    }
}

extension SpansExporter {
    struct Header: JSONFileHeader {
        let version: Int = 1
        let metadata: [String: [String: SpanMetadata.Value]]
        static var batchFieldName: String { "events" }
    }
}
