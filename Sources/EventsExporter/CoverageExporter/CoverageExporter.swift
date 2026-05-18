/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk
import CodeCoverageParser

internal final class CoverageExporter {
    let coverageDirectory = "com.datadog.civisibility/coverage/v1"
    let configuration: ExporterConfiguration
    let coverageStorage: FeatureStoreAndUpload

    init(config: ExporterConfiguration, api: TestImpactAnalysisApi) throws {
        self.configuration = config

        let filesOrchestrator = FilesOrchestrator(
            directory: try Directory(withSubdirectoryPath: coverageDirectory),
            performance: PerformancePreset.instantDataDelivery,
            dateProvider: SystemDateProvider()
        )

        let encoder = api.encoder
        let dataFormat = try DataFormat(header: Header(), encoder: encoder)

        let writer = FileWriter(entity: "coverage",
                                dataFormat: dataFormat,
                                orchestrator: filesOrchestrator,
                                encoder: encoder)
        let reader = FileReader(dataFormat: dataFormat, orchestrator: filesOrchestrator)
        let upload: ClosureDataUploader.UploadCallback = { (data: Data) async throws(HTTPClient.RequestError) -> Void in
            try await api.uploadCoverage(batch: data)
        }
        let uploader = ClosureDataUploader(upload: upload)
        self.coverageStorage = FeatureStoreAndUpload(featureName: "coverage",
                                                     reader: reader,
                                                     writer: writer,
                                                     performance: configuration.performancePreset,
                                                     uploader: uploader)
    }

    func exportCoverage(coverage: URL, parser: CoverageParser, workspacePath: String?,
                        testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64)
    {
        Log.debug("Start processing coverage: \(coverage.path)")
        var coverageData: TestCodeCoverage? = nil

        defer {
            if configuration.debug.saveCodeCoverageFiles {
                if let coverageData = coverageData, let data = try? JSONEncoder.apiEncoder.encode(coverageData) {
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
            coverageStorage.write(value: coverageData!)
        } catch {
            Log.print("Code coverage generation failed: \(error)")
            return
        }

        Log.debug("End processing coverage: \(coverage.path)")
    }

    func shutdown() {
        coverageStorage.stop()
    }
}

extension CoverageExporter {
    struct Header: JSONFileHeader {
        let version: Int = 2
        static var batchFieldName: String { "coverages" }
    }
}
