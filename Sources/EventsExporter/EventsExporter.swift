/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk
import CodeCoverage

public protocol EventsExporterProtocol: SpanExporter {
    var endpointURLs: Set<String> { get }
    
    func exportEvent<T: Encodable>(event: T)
    func searchCommits(repositoryURL: String, commits: [String]) -> [String]
    func export(coverage: URL, processor: CoverageProcessor, workspacePath: String?,
                testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64)
    func uploadPackFiles(packFilesDirectory: Directory, commit: String, repository: String) throws
    func skippableTests(repositoryURL: String, sha: String, testLevel: ITRTestLevel,
                        configurations: [String: String], customConfigurations: [String: String]) -> SkipTests?
    func tracerSettings(
        service: String, env: String, repositoryURL: String, branch: String, sha: String,
        testLevel: ITRTestLevel, configurations: [String: String], customConfigurations: [String: String]
    ) -> TracerSettings?
    func knownTests(
        service: String, env: String, repositoryURL: String,
        configurations: [String: String], customConfigurations: [String: String]
    ) -> KnownTestsMap?
}

public class EventsExporter: EventsExporterProtocol {
    let configuration: ExporterConfiguration
    var spansExporter: SpansExporter
    var logsExporter: LogsExporter
    var coverageExporter: CoverageExporter
    var itrService: ITRService
    var settingsService: SettingsService
    var knownTestsService: KnownTestsService

    public init(config: ExporterConfiguration) throws {
        self.configuration = config
        Log.setLogger(config.logger)
        spansExporter = try SpansExporter(config: configuration)
        logsExporter = try LogsExporter(config: configuration)
        coverageExporter = try CoverageExporter(config: configuration)
        itrService = try ITRService(config: configuration)
        settingsService = try SettingsService(config: configuration)
        knownTestsService = try KnownTestsService(config: configuration)
        Log.debug("EventsExporter created: \(spansExporter.runtimeId), endpoint: \(config.endpoint)")
    }

    public func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        // TODO: Honor the timeout
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

    public func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        // TODO: Honor the timeout
        logsExporter.logsStorage.writer.queue.sync {}
        spansExporter.spansStorage.writer.queue.sync {}
        coverageExporter.coverageStorage.writer.queue.sync {}

        _ = logsExporter.logsUpload.uploader.flush()
        _ = spansExporter.spansUpload.uploader.flush()
        _ = coverageExporter.coverageUpload.uploader.flush()

        return .success
    }

    public func export(coverage: URL, processor: CoverageProcessor, workspacePath: String?,
                       testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64)
    {
        coverageExporter.exportCoverage(coverage: coverage, processor: processor, workspacePath: workspacePath,
                                        testSessionId: testSessionId, testSuiteId: testSuiteId, spanId: spanId)
    }

    public func searchCommits(repositoryURL: String, commits: [String]) -> [String] {
        return itrService.searchExistingCommits(repositoryURL: repositoryURL, commits: commits)
    }

    public func uploadPackFiles(packFilesDirectory: Directory, commit: String, repository: String) throws {
        try itrService.uploadPackFiles(packFilesDirectory: packFilesDirectory, commit: commit, repository: repository)
    }

    public func skippableTests(
        repositoryURL: String, sha: String, testLevel: ITRTestLevel,
        configurations: [String: String], customConfigurations: [String: String]) -> SkipTests?
    {
        itrService.skippableTests(repositoryURL: repositoryURL, sha: sha,
                                  testLevel: testLevel,
                                  configurations: configurations,
                                  customConfigurations: customConfigurations)
    }

    public func tracerSettings(
        service: String, env: String, repositoryURL: String, branch: String, sha: String,
        testLevel: ITRTestLevel, configurations: [String: String], customConfigurations: [String: String]
    ) -> TracerSettings? {
        settingsService.settings(
            service: service, env: env, repositoryURL: repositoryURL,
            branch: branch, sha: sha, testLevel: testLevel, configurations: configurations,
            customConfigurations: customConfigurations
        )
    }
    
    public func knownTests(
        service: String, env: String, repositoryURL: String,
        configurations: [String: String], customConfigurations: [String: String]
    ) -> KnownTestsMap? {
        knownTestsService.tests(service: service, env: env, repositoryURL: repositoryURL,
                                configurations: configurations, customConfigurations: customConfigurations)
    }

    public func shutdown(explicitTimeout: TimeInterval?) {
        _ = self.flush(explicitTimeout: explicitTimeout)
    }

    public var endpointURLs: Set<String> {
        [configuration.endpoint.logsURL.absoluteString,
         configuration.endpoint.spansURL.absoluteString,
         configuration.endpoint.coverageURL.absoluteString,
         configuration.endpoint.searchCommitsURL.absoluteString,
         configuration.endpoint.skippableTestsURL.absoluteString,
         configuration.endpoint.packfileURL.absoluteString,
         configuration.endpoint.settingsURL.absoluteString,
         configuration.endpoint.knownTestsURL.absoluteString]
    }
}
