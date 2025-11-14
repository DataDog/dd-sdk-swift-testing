/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk
import CodeCoverageParser

internal class CoverageExporter {
    let coverageDirectory = "com.datadog.testoptimization/coverage/v1"
    let configuration: ExporterConfiguration
    let coverageStorage: FeatureStoreAndUpload

    init(config: ExporterConfiguration, api: TestImpactAnalysisApi) throws {
        self.configuration = config
        
        let filesOrchestrator = try FilesOrchestrator(
            directory: try Directory.cache().createSubdirectory(path: coverageDirectory),
            performance: configuration.performancePreset,
            dateProvider: SystemDateProvider()
        )
        
        let dataFormat = try DataFormat(header: Header(), encoder: api.encoder)

        let coverageFileWriter = FileWriter(
            entity: "coverage",
            dataFormat: dataFormat,
            orchestrator: filesOrchestrator,
            encoder: api.encoder
        )

        let coverageFileReader = FileReader(
            dataFormat: dataFormat,
            orchestrator: filesOrchestrator
        )
        
        let uploader = ClosureDataUploader { data, response in
            api.uploadCoverage(batch: data) { response($0.error) }
        }

        coverageStorage = .init(featureName: "coverage",
                                reader: coverageFileReader,
                                writer: coverageFileWriter,
                                performance: config.performancePreset,
                                uploader: uploader)
    }

    func exportCoverage(coverage: URL, parser: CoverageParser, workspacePath: String?,
                        testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64)
    {
        Log.debug("Start processing coverage: \(coverage.path)")
        var coverageData: TestCodeCoverage? = nil
        
        defer {
            if configuration.debugSaveCodeCoverageFiles {
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
            coverageStorage.writer.write(value: coverageData!) { _ in }
        } catch {
            Log.print("Code coverage generation failed: \(error)")
            return
        }
        
        Log.debug("End processing coverage: \(coverage.path)")
    }
}

private extension CoverageExporter {
    struct Header: JSONFileHeader {
        let version: String = "2"
        static var batchFieldName: String { "coverages" }
    }
}
