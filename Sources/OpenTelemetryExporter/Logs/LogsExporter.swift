/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
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

internal class LogsExporter {
    let logsDirectory = "com.datadog.civisibility/logs/v1"
    let configuration: ExporterConfiguration
    let logsStorage: FeatureStorage
    let logsUpload: FeatureUpload

    init(config: ExporterConfiguration) throws {
        self.configuration = config

        let filesOrchestrator = FilesOrchestrator(
            directory: try Directory(withSubdirectoryPath: logsDirectory),
            performance: configuration.performancePreset,
            dateProvider: SystemDateProvider()
        )

        let dataFormat = DataFormat(prefix: "[", suffix: "]", separator: ",")

        let logsFileWriter = FileWriter(
            dataFormat: dataFormat,
            orchestrator: filesOrchestrator
        )

        let logsFileReader = FileReader(
            dataFormat: dataFormat,
            orchestrator: filesOrchestrator
        )

        logsStorage = FeatureStorage(writer: logsFileWriter, reader: logsFileReader)

        let requestBuilder = RequestBuilder(
            url: configuration.endpoint.logsURL,
            queryItems: [
                .ddsource(source: configuration.source)
            ],
            headers: [
                .contentTypeHeader(contentType: .applicationJSON),
                .userAgentHeader(
                    appName: configuration.applicationName,
                    appVersion: configuration.version,
                    device: Device.current
                ),
                .ddAPIKeyHeader(apiKey: configuration.apiKey)
            ] + (configuration.payloadCompression ? [RequestBuilder.HTTPHeader.contentEncodingHeader(contentEncoding: .deflate)] : [])
        )

        logsUpload = FeatureUpload(featureName: "logsUpload",
                                   storage: logsStorage,
                                   requestBuilder: requestBuilder,
                                   performance: configuration.performancePreset)
    }

    func exportLogs(fromSpan span: SpanData) {
        span.events.forEach {
            let log = DDLog(event: $0, span: span, configuration: configuration)
            if configuration.performancePreset.synchronousWrite {
                logsStorage.writer.writeSync(value: log)
            } else {
                logsStorage.writer.write(value: log)
            }
        }
    }
}
