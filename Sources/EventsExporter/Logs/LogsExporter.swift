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

internal final class LogsExporter: LogRecordExporter {
    let synchronousWrite: Bool
    let logsStorage: FeatureStoreAndUpload

    init(config: ExporterConfiguration, storage: Directory, api: LogsApi) throws {
        self.synchronousWrite = config.performancePreset.synchronousWrite

        let filesOrchestrator = FilesOrchestrator(
            directory: try storage.createSubdirectory(path: "v1"),
            performance: config.performancePreset,
            dateProvider: SystemDateProvider()
        )

        let encoder = api.encoder
        let dataFormat = DataFormat.jsonArray

        let writer = FileWriter(entity: "logs",
                                dataFormat: dataFormat,
                                orchestrator: filesOrchestrator,
                                encoder: encoder,
                                log: config.logger)
        let reader = FileReader(dataFormat: dataFormat, orchestrator: filesOrchestrator)
        let uploadSync: ClosureDataUploader.UploadCallbackSync = { (data, timeout) throws(APICallError) -> Void in
            try api.uploadLogs(batch: data, observer: nil, timeout: timeout)
        }
        let uploadAsync: ClosureDataUploader.UploadCallbackAsync = { (data, timeout) async throws(APICallError) -> Void in
            try await api.uploadLogs(batch: data, observer: nil, timeout: timeout)
        }
        let uploader = ClosureDataUploader(sync: uploadSync, async: uploadAsync)
        self.logsStorage = FeatureStoreAndUpload(featureName: "logs",
                                                 reader: reader,
                                                 writer: writer,
                                                 performance: config.performancePreset,
                                                 uploader: uploader,
                                                 log: config.logger)
    }

    private func writeLog(_ log: DDLog) {
        if synchronousWrite {
            try? logsStorage.writeSync(value: log)
        } else {
            logsStorage.write(value: log)
        }
    }

    // MARK: - OpenTelemetrySdk.LogRecordExporter

    func export(logRecords: [ReadableLogRecord], explicitTimeout: TimeInterval?) -> ExportResult {
        for record in logRecords {
            guard let context = record.spanContext else { continue }
            writeLog(DDLog(log: record, span: context))
        }
        return .success
    }

    func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult {
        (try? logsStorage.flush(timeout: explicitTimeout)) == true ? .success : .failure
    }

    func shutdown(explicitTimeout: TimeInterval?) {
        logsStorage.stop()
    }

    func export(logRecords: [ReadableLogRecord], explicitTimeout: TimeInterval?) async -> ExportResult {
        for record in logRecords {
            guard let context = record.spanContext else { continue }
            writeLog(DDLog(log: record, span: context))
        }
        return .success
    }

    func forceFlush(explicitTimeout: TimeInterval?) async -> ExportResult {
        (try? logsStorage.flush()) == true ? .success : .failure
    }

    func shutdown(explicitTimeout: TimeInterval?) async {
        logsStorage.stop()
    }
}
