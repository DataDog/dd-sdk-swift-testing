/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
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
            performance: PerformancePreset.instantDataDelivery,
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
                .apiKeyHeader(apiKey: config.apiKey)
            ] // + (configuration.payloadCompression ? [HTTPHeader.contentEncodingHeader(contentEncoding: .deflate)] : [])
        )

        coverageUpload = FeatureUpload(featureName: "coverageUpload",
                                       storage: coverageStorage,
                                       requestBuilder: requestBuilder,
                                       performance: configuration.performancePreset,
                                       debug: config.debug.logNetworkRequests)
        requestBuilder.addFieldsCallback = addCoverage
    }

    func exportCoverage(coverage: URL, testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64, workspacePath: String?, binaryImagePaths: [String]) {
        Log.debug("Start processing coverage: \(coverage.path)")
        let profData: URL
        do {
            profData = try DDCoverageConversor.generateProfData(profrawFile: coverage)
        } catch {
            Log.print("Profiler Data generation failed: \(error)")
            return
        }
        
        let ddCoverage = DDCoverageConversor.getDatadogCoverage(profdataFile: profData, testSessionId: testSessionId,
                                                                testSuiteId: testSuiteId, spanId: spanId, workspacePath: workspacePath,
                                                                binaryImagePaths: binaryImagePaths)

        if configuration.debug.saveCodeCoverageFiles {
            let data = try? JSONEncoder.default().encode(ddCoverage)
            let testName = coverage.deletingPathExtension().lastPathComponent.components(separatedBy: "__").last!
            let jsonURL = coverage.deletingLastPathComponent().appendingPathComponent(testName).appendingPathExtension("json")
            try? data?.write(to: jsonURL)
        } else {
            try? FileManager.default.removeItem(at: coverage)
            try? FileManager.default.removeItem(at: profData)
        }
        coverageStorage.writer.write(value: ddCoverage)
        Log.debug("End processing coverage: \(coverage.path)")
    }

    private func addCoverage(request: MultipartFormDataRequest, data: Data?) {
        guard let data = data,
              let newline = Character("\n").asciiValue else { return }

        let separatedData = data.split(separator: newline)
        separatedData.enumerated().forEach {
            request.addDataField(named: "coverage\($0)", data: $1, mimeType: .applicationJSON)
        }
        request.addDataField(named: "event", data: #"{"dummy": true}"#.data(using: .utf8)!, mimeType: .applicationJSON)
    }
}
