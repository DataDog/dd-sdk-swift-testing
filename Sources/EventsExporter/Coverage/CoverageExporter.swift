/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

internal class CoverageExporter {
    let coverageDirectory = "com.datadog.civisibility/coverage/v1"
    let configuration: ExporterConfiguration
    let coverageStorage: FeatureStorage
    let coverageUpload: FeatureUpload

    init(config: ExporterConfiguration) throws {
        self.configuration = config

        let filesOrchestrator = FilesOrchestrator(
            directory: try Directory(withSubdirectoryPath: coverageDirectory),
            performance: configuration.performancePreset,
            dateProvider: SystemDateProvider()
        )

        let genericMetadata = """
        "*": { "env": "\(configuration.environment)", "runtime-id": "\(UUID().uuidString)", "language": "swift", "library_version": "\(configuration.libraryVersion)"}
        """

        let prefix = """
        {"version": 1, "metadata": { \(genericMetadata) }, "events": [
        """

        let suffix = "]}"

        let dataFormat = DataFormat(prefix: prefix, suffix: suffix, separator: ",")

        let coverageFileWriter = FileWriter(
            dataFormat: dataFormat,
            orchestrator: filesOrchestrator
        )

        let coverageFileReader = FileReader(
            dataFormat: dataFormat,
            orchestrator: filesOrchestrator
        )

        coverageStorage = FeatureStorage(writer: coverageFileWriter, reader: coverageFileReader)

        let requestBuilder = RequestBuilder(
            url: configuration.endpoint.coverageURL,
            queryItems: [],
            headers: [
                .contentTypeHeader(contentType: .applicationJSON),
                .userAgentHeader(
                    appName: configuration.applicationName,
                    appVersion: configuration.version,
                    device: Device.current
                ),
                .ddAPIKeyHeader(apiKey: config.apiKey)
            ] + (configuration.payloadCompression ? [RequestBuilder.HTTPHeader.contentEncodingHeader(contentEncoding: .deflate)] : [])
        )

        coverageUpload = FeatureUpload(featureName: "coverageUpload",
                                       storage: coverageStorage,
                                       requestBuilder: requestBuilder,
                                       performance: configuration.performancePreset)
    }

    func exportCoverage(span: SpanData) {}
}
