/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk
import CodeCoverageParser

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
        
        let prefix = """
        {
        "version": 2,
        "coverages": [
        """

        let suffix = "]\n}"

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

    func exportCoverage(coverage: URL, parser: CoverageParser, workspacePath: String?,
                        testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64)
    {
        Log.debug("Start processing coverage: \(coverage.path)")
        var coverageData: TestCodeCoverage? = nil
        
        defer {
            if configuration.debug.saveCodeCoverageFiles {
                if let coverageData = coverageData, let data = try? JSONEncoder.default().encode(coverageData) {
                    let testName = coverage.deletingPathExtension().lastPathComponent.components(separatedBy: "__").last!
                    let jsonURL = coverage.deletingLastPathComponent()
                        .appendingPathComponent(testName + ".json", isDirectory: false)
                    try? data.write(to: jsonURL)
                }
            } else {
                try? FileManager.default.removeItem(at: coverage)
            }
        }
        
        do {
            let info = try parser.filesCovered(in: coverage)
            coverageData = TestCodeCoverage(sessionId: testSessionId,
                                            suiteId: testSuiteId,
                                            spanId: spanId,
                                            workspace: workspacePath,
                                            files: info.files.values)
            coverageStorage.writer.write(value: coverageData!)
        } catch {
            Log.print("Code coverage generation failed: \(error)")
            return
        }
        
        Log.debug("End processing coverage: \(coverage.path)")
    }

    private func addCoverage(request: MultipartFormDataRequest, data: Data?) {
        guard let data = data else { return }
        request.addDataField(named: "coverage", data: data, mimeType: .applicationJSON)
        request.addDataField(named: "event", data: #"{"dummy": true}"#.data(using: .utf8)!, mimeType: .applicationJSON)
    }
}

