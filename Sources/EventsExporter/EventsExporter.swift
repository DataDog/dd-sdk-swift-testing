/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk
import CodeCoverageParser

/// Thrown by `EventsExporterProtocol` library configuration requests
/// (`tracerSettings`, `skippableTests`, `knownTests`, `testManagementTests`).
/// Carries enough context (request name, payload, and the failure reason) for
/// the caller to log a meaningful diagnostic. `.unauthorized` and
/// `.communicationFailed` count as communication failures with the backend;
/// the other reasons surface payload encoding or response decoding issues.
public struct LibraryConfigurationCommunicationError: Error, CustomStringConvertible {
    public enum Reason {
        /// The request payload could not be encoded as JSON.
        case payloadEncodingFailed
        /// The backend rejected the request with HTTP 401 or 403, usually
        /// meaning that DD_API_KEY is missing or incorrect.
        case unauthorized
        /// The backend could not be reached: transport error, non-2xx HTTP
        /// status, or an inconsistent URLSession response. The underlying
        /// upload error is included.
        case communicationFailed(any Error)
        /// The backend responded but the body could not be decoded into the
        /// expected shape. The raw response body and the decoding error are
        /// both included.
        case responseDecodingFailed(body: Data, error: any Error)
    }

    public let requestName: String
    public let payload: String
    public let reason: Reason

    public init(requestName: String, payload: String, reason: Reason) {
        self.requestName = requestName
        self.payload = payload
        self.reason = reason
    }

    public var description: String {
        var lines: [String]
        switch reason {
        case .payloadEncodingFailed:
            lines = ["\(requestName): request payload could not be encoded"]
        case .unauthorized:
            lines = ["\(requestName): Datadog backend rejected the request as unauthorized. " +
                     "Please verify that DD_API_KEY is correct."]
        case .communicationFailed(let error):
            lines = ["\(requestName): no response from backend: \(error)"]
        case .responseDecodingFailed(let body, let error):
            lines = ["\(requestName): invalid response body: \(error)",
                     "Response: \(String(decoding: body, as: UTF8.self))"]
        }
        lines.append("Payload: \(payload)")
        return lines.joined(separator: "\n")
    }
}

public protocol EventsExporterProtocol: SpanExporter {
    var endpointURLs: Set<String> { get }
    var maxObjectSize: UInt64 { get }

    func exportEvent<T: Encodable>(event: T)
    func searchCommits(
        repositoryURL: String, commits: [String]
    ) throws(LibraryConfigurationCommunicationError) -> [String]
    func export(coverage: URL, parser: CoverageParser, workspacePath: String?,
                testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64)
    func uploadPackFiles(packFilesDirectory: Directory, commit: String, repository: String) throws
    func skippableTests(repositoryURL: String, sha: String, testLevel: ITRTestLevel,
                        configurations: [String: String], customConfigurations: [String: String]
    ) throws(LibraryConfigurationCommunicationError) -> SkipTests
    func tracerSettings(
        service: String, env: String, repositoryURL: String, branch: String, sha: String,
        testLevel: ITRTestLevel, configurations: [String: String], customConfigurations: [String: String]
    ) throws(LibraryConfigurationCommunicationError) -> TracerSettings
    func knownTests(
        service: String, env: String, repositoryURL: String,
        configurations: [String: String], customConfigurations: [String: String]
    ) throws(LibraryConfigurationCommunicationError) -> KnownTestsMap
    func testManagementTests(
        repositoryURL: String, sha: String?, commitMessage: String?, module: String?, branch: String?
    ) throws(LibraryConfigurationCommunicationError) -> TestManagementTestsInfo
}

public final class EventsExporter: EventsExporterProtocol {
    let configuration: ExporterConfiguration
    var spansExporter: SpansExporter
    var logsExporter: LogsExporter
    var coverageExporter: CoverageExporter
    var itrService: ITRService
    var settingsService: SettingsService
    var knownTestsService: KnownTestsService
    var testManagementService: TestManagementService

    public var maxObjectSize: UInt64 { configuration.performancePreset.maxObjectSize }

    public init(config: ExporterConfiguration) throws {
        self.configuration = config
        Log.setLogger(config.logger)
        spansExporter = try SpansExporter(config: configuration)
        logsExporter = try LogsExporter(config: configuration)
        coverageExporter = try CoverageExporter(config: configuration)
        itrService = try ITRService(config: configuration)
        settingsService = try SettingsService(config: configuration)
        knownTestsService = try KnownTestsService(config: configuration)
        testManagementService = try TestManagementService(config: configuration)
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

    public func export(coverage: URL, parser: CoverageParser, workspacePath: String?,
                       testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64)
    {
        coverageExporter.exportCoverage(coverage: coverage, parser: parser, workspacePath: workspacePath,
                                        testSessionId: testSessionId, testSuiteId: testSuiteId, spanId: spanId)
    }

    public func searchCommits(
        repositoryURL: String, commits: [String]
    ) throws(LibraryConfigurationCommunicationError) -> [String] {
        try itrService.searchExistingCommits(repositoryURL: repositoryURL, commits: commits)
    }

    public func uploadPackFiles(packFilesDirectory: Directory, commit: String, repository: String) throws {
        try itrService.uploadPackFiles(packFilesDirectory: packFilesDirectory, commit: commit, repository: repository)
    }

    public func skippableTests(
        repositoryURL: String, sha: String, testLevel: ITRTestLevel,
        configurations: [String: String], customConfigurations: [String: String]
    ) throws(LibraryConfigurationCommunicationError) -> SkipTests {
        try itrService.skippableTests(repositoryURL: repositoryURL, sha: sha,
                                      testLevel: testLevel,
                                      configurations: configurations,
                                      customConfigurations: customConfigurations)
    }

    public func tracerSettings(
        service: String, env: String, repositoryURL: String, branch: String, sha: String,
        testLevel: ITRTestLevel, configurations: [String: String], customConfigurations: [String: String]
    ) throws(LibraryConfigurationCommunicationError) -> TracerSettings {
        try settingsService.settings(
            service: service, env: env, repositoryURL: repositoryURL,
            branch: branch, sha: sha, testLevel: testLevel, configurations: configurations,
            customConfigurations: customConfigurations
        )
    }

    /// Returns all known tests by fetching every page and merging results.
    public func knownTests(
        service: String, env: String, repositoryURL: String,
        configurations: [String: String], customConfigurations: [String: String]
    ) throws(LibraryConfigurationCommunicationError) -> KnownTestsMap {
        try knownTestsService.tests(service: service, env: env, repositoryURL: repositoryURL,
                                    configurations: configurations,
                                    customConfigurations: customConfigurations).tests
    }

    /// Returns a single page of known tests with pagination info when provided.
    public func knownTests(
        service: String, env: String, repositoryURL: String,
        configurations: [String: String], customConfigurations: [String: String],
        page: KnownTestsPageInfo
    ) throws(LibraryConfigurationCommunicationError) -> KnownTestsResult {
        try knownTestsService.tests(service: service, env: env, repositoryURL: repositoryURL,
                                    configurations: configurations, customConfigurations: customConfigurations,
                                    pageInfo: page)
    }

    public func testManagementTests(
        repositoryURL: String, sha: String? = nil, commitMessage: String? = nil, module: String? = nil, branch: String? = nil
    ) throws(LibraryConfigurationCommunicationError) -> TestManagementTestsInfo {
        try testManagementService.tests(repositoryURL: repositoryURL, sha: sha, commitMessage: commitMessage, module: module, branch: branch)
    }

    public func shutdown(explicitTimeout: TimeInterval?) {
        _ = self.flush(explicitTimeout: explicitTimeout)
        logsExporter.shutdown()
        spansExporter.shutdown()
        coverageExporter.shutdown()
    }

    public var endpointURLs: Set<String> {
        [configuration.endpoint.logsURL.absoluteString,
         configuration.endpoint.spansURL.absoluteString,
         configuration.endpoint.coverageURL.absoluteString,
         configuration.endpoint.searchCommitsURL.absoluteString,
         configuration.endpoint.skippableTestsURL.absoluteString,
         configuration.endpoint.packfileURL.absoluteString,
         configuration.endpoint.settingsURL.absoluteString,
         configuration.endpoint.knownTestsURL.absoluteString,
         configuration.endpoint.testManagementTestsURL.absoluteString]
    }
}
