/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

public protocol SpansExporterType: OpenTelemetrySdk.SpanExporter {
    func setMetadata(_ meta: SpanMetadata)
}

internal class SpansExporter: SpansExporterType {
    let spansDirectory = "com.datadog.testoptimization/spans/v1"
    let configuration: ExporterConfiguration
    let spansStorage: FeatureStoreAndUpload
    let encoder: JSONEncoder
    //let runtimeId: String

    init(config: ExporterConfiguration, api: SpansApi) throws {
        self.configuration = config
        self.encoder = api.encoder

        let filesOrchestrator = try FilesOrchestrator(
            directory: try Directory.cache().createSubdirectory(path: spansDirectory),
            performance: configuration.performancePreset,
            dateProvider: SystemDateProvider()
        )

        let dataFormat = try DataFormat(header: Header(metadata: config.metadata.metadata),
                                        encoder: encoder)

        let spanFileWriter = FileWriter(
            entity: "spans",
            dataFormat: dataFormat,
            orchestrator: filesOrchestrator,
            encoder: encoder
        )

        let spanFileReader = FileReader(
            dataFormat: dataFormat,
            orchestrator: filesOrchestrator
        )
        
        let uploader = ClosureDataUploader { data in
            api.uploadSpans(batch: data)
        }
        
        spansStorage = .init(featureName: "spans",
                             reader: spanFileReader,
                             writer: spanFileWriter,
                             performance: configuration.performancePreset,
                             uploader: uploader)
    }
    
    func setMetadata(_ meta: SpanMetadata) {
        // metadata always encodes
        let dataFormat = try! DataFormat(header: Header(metadata: meta.metadata),
                                         encoder: encoder)
        spansStorage.update(dataFormat: dataFormat)
    }

    func exportSpan(span: SpanData) {
        if span.attributes["type"]?.description == "test" {
            let ciTestEnvelope = CITestEnvelope(DDSpan(spanData: span, serviceName: configuration.serviceName, applicationVersion: configuration.applicationVersion))
            if configuration.performancePreset.synchronousWrite {
                try? spansStorage.writeSync(value: ciTestEnvelope)
            } else {
                let _ = spansStorage.write(value: ciTestEnvelope)
            }
        } else {
            let spanEnvelope = SpanEnvelope(DDSpan(spanData: span, serviceName: configuration.serviceName, applicationVersion: configuration.applicationVersion))
            if configuration.performancePreset.synchronousWrite {
                try? spansStorage.writer.writeSync(value: spanEnvelope)
            } else {
                let _ = spansStorage.writer.write(value: spanEnvelope)
            }
        }
    }
    
    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        for span in spans {
            exportSpan(span: span)
        }
        return .success
    }
    
    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        do {
            return try spansStorage.flush() ? .success : .failure
        } catch {
            return .failure
        }
    }
    
    func shutdown(explicitTimeout: TimeInterval?) {
        spansStorage.stop()
    }
}

extension SpansExporter {
    struct Header: JSONFileHeader {
        let version: String = "1"
        let metadata: [String: [String: SpanMetadata.Value]]
        static var batchFieldName: String { "events" }
    }
}


internal class MultiSpanExporter: SpansExporterType {
    var spanExporters: [SpansExporterType]
    var exporter: OpenTelemetrySdk.MultiSpanExporter
    
    init(spanExporters: [SpansExporterType]) {
        self.spanExporters = spanExporters
        self.exporter = .init(spanExporters: spanExporters)
    }
    
    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        exporter.export(spans: spans, explicitTimeout: explicitTimeout)
    }
    
    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        exporter.flush(explicitTimeout: explicitTimeout)
    }
    
    func shutdown(explicitTimeout: TimeInterval?) {
        exporter.shutdown(explicitTimeout: explicitTimeout)
    }
    
    func setMetadata(_ meta: SpanMetadata) {
        for spanExporter in spanExporters {
            spanExporter.setMetadata(meta)
        }
    }
}
