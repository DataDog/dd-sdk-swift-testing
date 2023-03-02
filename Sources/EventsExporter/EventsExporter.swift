/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

public class EventsExporter: SpanExporter {
    let configuration: ExporterConfiguration
    var spansExporter: SpansExporter
    var logsExporter: LogsExporter
    var coverageExporter: CoverageExporter
    var itrService: ITRService

    public init(config: ExporterConfiguration) throws {
        self.configuration = config
        spansExporter = try SpansExporter(config: configuration)
        logsExporter = try LogsExporter(config: configuration)
        coverageExporter = try CoverageExporter(config: configuration)
        itrService = try ITRService(config: configuration)
        Log.debug("EventsExporter created: \(spansExporter.runtimeId)")
    }

    public func export(spans: [SpanData]) -> SpanExporterResultCode {
        spans.forEach {
            if $0.traceFlags.sampled {
                spansExporter.exportSpan(span: $0)
            }
            if $0.traceFlags.sampled {
                logsExporter.exportLogs(fromSpan: $0)
            }
        }
        return .success
    }

    public func exportEvent<T: Encodable>(event: T) {
        if configuration.performancePreset.synchronousWrite {
            spansExporter.spansStorage.writer.writeSync(value: event)
        } else {
            spansExporter.spansStorage.writer.write(value: event)
        }
    }

    public func flush() -> SpanExporterResultCode {
        logsExporter.logsStorage.writer.queue.sync {}
        spansExporter.spansStorage.writer.queue.sync {}
        coverageExporter.coverageStorage.writer.queue.sync {}

        _ = logsExporter.logsUpload.uploader.flush()
        _ = spansExporter.spansUpload.uploader.flush()
        _ = coverageExporter.coverageUpload.uploader.flush()

        return .success
    }

    public func export(coverage: URL, testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64, workspacePath: String?, binaryImagePaths: [String]) {
        coverageExporter.exportCoverage(coverage: coverage, testSessionId: testSessionId, testSuiteId: testSuiteId, spanId: spanId, workspacePath: workspacePath, binaryImagePaths: binaryImagePaths)
    }

    public func searchCommits(repositoryURL: String, commits: [String]) -> [String] {
        return itrService.searchExistingCommits(repositoryURL: repositoryURL, commits: commits)
    }

    public func uploadPackFiles(packFilesDirectory: Directory, commit: String, repository: String) {
        try? itrService.uploadPackFiles(packFilesDirectory: packFilesDirectory,
                                        commit: commit,
                                        repository: repository)
    }

    public func skippableTests(repositoryURL: String, sha: String, configurations: [String: String], customConfigurations: [String: String]) -> [SkipTestPublicFormat] {
        return itrService.skippableTests(repositoryURL: repositoryURL, sha: sha, configurations: configurations, customConfigurations: customConfigurations)
    }

    public func itrSetting(service: String, env: String, repositoryURL: String, branch: String, sha: String, configurations: [String: String], customConfigurations: [String: String]) -> (codeCoverage: Bool, testsSkipping: Bool)? {
        return itrService.itrSetting(service: service, env: env, repositoryURL: repositoryURL, branch: branch, sha: sha, configurations: configurations, customConfigurations: customConfigurations)
    }

    public func shutdown() {
        _ = self.flush()
    }

    public func endpointURLs() -> Set<String> {
        return [configuration.endpoint.logsURL.absoluteString,
                configuration.endpoint.spansURL.absoluteString,
                configuration.endpoint.coverageURL.absoluteString,
                configuration.endpoint.searchCommitsURL.absoluteString,
                configuration.endpoint.skippableTestsURL.absoluteString,
                configuration.endpoint.packfileURL.absoluteString,
                configuration.endpoint.itrSettingsURL.absoluteString]
    }
}
