/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

internal enum LogLevel: Int, Codable {
    case debug
    case info
    case notice
    case warn
    case error
    case critical
}

internal enum LogConstants {
    static let ddSource = "ios"
    static let ddProduct = "datadog.product:citest"
}

public protocol LogsExporterType: OpenTelemetrySdk.LogRecordExporter {
    func exportLogs(fromSpan span: SpanData)
}

internal class LogsExporter: LogsExporterType {
    let logsDirectory = "com.datadog.civisibility/logs/v1"
    //let configuration: ExporterConfiguration
    let synchronousWrite: Bool
    let logsStorage: FeatureStoreAndUpload

    init(config: ExporterConfiguration, api: LogsApi) throws {
        //self.configuration = config
        self.synchronousWrite = config.performancePreset.synchronousWrite

        let filesOrchestrator = try FilesOrchestrator(
            directory: try Directory.cache().createSubdirectory(path: logsDirectory),
            performance: config.performancePreset,
            dateProvider: SystemDateProvider()
        )

        let dataFormat = DataFormat.jsonArray

        let logsFileWriter = FileWriter(
            entity: "logs",
            dataFormat: dataFormat,
            orchestrator: filesOrchestrator,
            encoder: .apiEncoder
        )

        let logsFileReader = FileReader(
            dataFormat: dataFormat,
            orchestrator: filesOrchestrator
        )
        
        let uploader = ClosureDataUploader { data in
            api.uploadLogs(batch: data)
        }

        logsStorage = FeatureStoreAndUpload(featureName: "logs",
                                            reader: logsFileReader,
                                            writer: logsFileWriter,
                                            performance: config.performancePreset,
                                            uploader: uploader)
    }
    
    func export(logRecords: [ReadableLogRecord], explicitTimeout: TimeInterval?) -> ExportResult {
        logRecords.forEach {
            if let context = $0.spanContext {
                _writeLog(DDLog(log: $0, span: context))
            }
        }
        return .success
    }

    func exportLogs(fromSpan span: SpanData) {
        span.events.forEach {
            _writeLog(DDLog(event: $0, span: span))
        }
    }
    
    func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult {
        do {
            return try logsStorage.flush() ? .success : .failure
        } catch {
            return .failure
        }
    }
    
    func shutdown(explicitTimeout: TimeInterval?) {
        logsStorage.stop()
    }
    
    private func _writeLog(_ log: DDLog) {
        if synchronousWrite {
            try? logsStorage.writeSync(value: log)
        } else {
            let _ = logsStorage.write(value: log)
        }
    }
}

internal class SpanEventsLogExporterAdapter: SpansExporterType {
    var logsExporter: LogsExporterType
    
    init(logsExporter: LogsExporterType) {
        self.logsExporter = logsExporter
    }
    
    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        spans.forEach { logsExporter.exportLogs(fromSpan: $0) }
        return .success
    }
    
    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        .success
    }
    
    func shutdown(explicitTimeout: TimeInterval?) {}
    
    func setMetadata(_ meta: SpanMetadata) {}
}
