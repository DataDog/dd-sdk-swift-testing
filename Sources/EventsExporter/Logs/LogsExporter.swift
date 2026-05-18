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

internal final class LogsExporter {
    let logsDirectory = "com.datadog.civisibility/logs/v1"
    let configuration: ExporterConfiguration
    let logsStorage: FeatureStoreAndUpload

    init(config: ExporterConfiguration, api: LogsApi) throws {
        self.configuration = config

        let filesOrchestrator = FilesOrchestrator(
            directory: try Directory(withSubdirectoryPath: logsDirectory),
            performance: configuration.performancePreset,
            dateProvider: SystemDateProvider()
        )

        let encoder = api.encoder
        let dataFormat = DataFormat.jsonArray

        let writer = FileWriter(entity: "logs",
                                dataFormat: dataFormat,
                                orchestrator: filesOrchestrator,
                                encoder: encoder)
        let reader = FileReader(dataFormat: dataFormat, orchestrator: filesOrchestrator)
        let upload: ClosureDataUploader.UploadCallback = { (data: Data) async throws(HTTPClient.RequestError) -> Void in
            try await api.uploadLogs(batch: data)
        }
        let uploader = ClosureDataUploader(upload: upload)
        self.logsStorage = FeatureStoreAndUpload(featureName: "logs",
                                                 reader: reader,
                                                 writer: writer,
                                                 performance: configuration.performancePreset,
                                                 uploader: uploader)
    }

    func exportLogs(fromSpan span: SpanData) {
        span.events.forEach {
            let log = DDLog(event: $0, span: span, configuration: configuration)
            if configuration.performancePreset.synchronousWrite {
                try? logsStorage.writeSync(value: log)
            } else {
                logsStorage.write(value: log)
            }
        }
    }

    func shutdown() {
        logsStorage.stop()
    }
}
