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

internal class LogsExporter {
    let logsDirectory = "com.datadog.civisibility/logs/v1"
    let configuration: ExporterConfiguration
    let logsStorage: FeatureStoreAndUpload

    init(config: ExporterConfiguration, api: LogsApi) throws {
        self.configuration = config

        let filesOrchestrator = try FilesOrchestrator(
            directory: try Directory.cache().createSubdirectory(path: logsDirectory),
            performance: configuration.performancePreset,
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
        
        let uploader = ClosureDataUploader { data, response in
            api.uploadLogs(batch: data) { response($0.error) }
        }

        logsStorage = FeatureStoreAndUpload(featureName: "logs",
                                            reader: logsFileReader,
                                            writer: logsFileWriter,
                                            performance: config.performancePreset,
                                            uploader: uploader)
    }

    func exportLogs(fromSpan span: SpanData) {
        span.events.forEach {
            let log = DDLog(event: $0, span: span, configuration: configuration)
            if configuration.performancePreset.synchronousWrite {
                try? logsStorage.writeSync(value: log)
            } else {
                logsStorage.write(value: log) { _ in }
            }
        }
    }
}
