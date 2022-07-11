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
            performance: PerformancePreset.coverageDataDelivery,
            dateProvider: SystemDateProvider()
        )

        let dataFormat = DataFormat(prefix: "", suffix: "", separator: "\n")

        let coverageFileWriter = FileWriter(
            dataFormat: dataFormat,
            orchestrator: filesOrchestrator
        )

        let coverageFileReader = FileReader(
            dataFormat: dataFormat,
            orchestrator: filesOrchestrator
        )

        coverageStorage = FeatureStorage(writer: coverageFileWriter, reader: coverageFileReader)

        let requestBuilder = MultipartRequestBuilder(
            url: configuration.endpoint.coverageURL,
            queryItems: [],
            headers: [
                .userAgentHeader(
                    appName: configuration.applicationName,
                    appVersion: configuration.version,
                    device: Device.current
                ),
                .ddAPIKeyHeader(apiKey: config.apiKey)
            ] // + (configuration.payloadCompression ? [HTTPHeader.contentEncodingHeader(contentEncoding: .deflate)] : [])
        )

        coverageUpload = FeatureUpload(featureName: "coverageUpload",
                                       storage: coverageStorage,
                                       requestBuilder: requestBuilder,
                                       performance: configuration.performancePreset)
        requestBuilder.addFieldsCallback = addCoverage
    }

    func exportCoverage(coverage: URL, traceId: UInt64, spanId: UInt64, workspacePath: String?, binaryImagePaths: [String]) {
        let profData = DDCoverageConversor.generateProfData(profrawFile: coverage)
        let ddCoverage = DDCoverageConversor.getDatadogCoverage(profdataFile: profData, traceId: traceId, spanId: spanId, workspacePath: workspacePath, binaryImagePaths: binaryImagePaths)
        coverageStorage.writer.write(value: ddCoverage)
    }

    private func addCoverage(request: MultipartFormDataRequest, data: Data?) {
        guard let data = data else { return }
        request.addDataField(named: "coverage1", data: data, mimeType: .applicationJSON)
        request.addDataField(named: "event", data: #"{"dummy": true}"#.data(using: .utf8)!, mimeType: .applicationJSON)
    }
}
