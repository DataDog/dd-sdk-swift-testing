/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk
import CodeCoverageParser

/// Thrown by `EventsExporterProtocol` requests that need to surface a
/// backend communication failure to the caller — library configuration
/// (`tracerSettings`, `skippableTests`, `knownTests`, `testManagementTests`)
/// as well as the git-upload pair (`searchCommits`, `uploadPackFiles`).
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

    /// Translate an `APICallError` from the new API wrappers into the
    /// public configuration-error shape. The request payload, when not
    /// captured by the caller, is rendered as a best-effort summary.
    init(requestName: String, payload: String, error: APICallError) {
        let reason: Reason
        switch error {
        case .httpError(code: 401, headers: _, body: _),
             .httpError(code: 403, headers: _, body: _):
            reason = .unauthorized
        case .httpError, .transport:
            reason = .communicationFailed(error)
        case .encoding:
            reason = .payloadEncodingFailed
        case .decoding(let body, let decodingError):
            reason = .responseDecodingFailed(body: body, error: decodingError)
        case .idMismatch, .typeMismatch:
            reason = .communicationFailed(error)
        case .fileSystem(let underlying), .unknownError(let underlying):
            reason = .communicationFailed(underlying)
        }
        self.init(requestName: requestName, payload: payload, reason: reason)
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

    let api: TestOptimizationApiService

    public var maxObjectSize: UInt64 { configuration.performancePreset.maxObjectSize }

    public init(config: ExporterConfiguration) throws {
        self.configuration = config
        Log.setLogger(config.logger)
        spansExporter = try SpansExporter(config: configuration)
        logsExporter = try LogsExporter(config: configuration)
        coverageExporter = try CoverageExporter(config: configuration)

        let apiConfig = APIServiceConfig(
            applicationName: config.applicationName,
            version: config.version,
            device: .current,
            hostname: config.hostname,
            apiKey: config.apiKey,
            endpoint: config.endpoint,
            clientId: config.exporterId,
            payloadCompression: false
        )
        self.api = TestOptimizationApiService(
            config: apiConfig,
            httpClient: HTTPClient(debug: config.debug.logNetworkRequests),
            log: config.logger
        )

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
        try invoke(requestName: "SearchCommitsRequest",
                   payload: "commits: \(commits)") { api throws(APICallError) in
            try await api.git.searchCommits(repositoryURL: repositoryURL, commits: commits)
        }
    }

    public func uploadPackFiles(packFilesDirectory: Directory, commit: String, repository: String) throws {
        Log.debug("Uploading packfiles from: \(packFilesDirectory.url) for commit: \(commit) in repo: \(repository)")
        try invoke(requestName: "PackFileRequest",
                   payload: "commit: \(commit)") { api throws(APICallError) in
            try await api.git.uploadPackFiles(directory: packFilesDirectory.url,
                                              commit: commit, repositoryURL: repository)
        }
    }

    public func skippableTests(
        repositoryURL: String, sha: String, testLevel: ITRTestLevel,
        configurations: [String: String], customConfigurations: [String: String]
    ) throws(LibraryConfigurationCommunicationError) -> SkipTests {
        try invoke(requestName: "SkipTestsRequest",
                   payload: "sha: \(sha)") { api throws(APICallError) in
            try await api.tia.skippableTests(repositoryURL: repositoryURL, sha: sha,
                                             environment: self.configuration.environment,
                                             service: self.configuration.serviceName,
                                             testLevel: testLevel,
                                             configurations: configurations,
                                             customConfigurations: customConfigurations)
        }
    }

    public func tracerSettings(
        service: String, env: String, repositoryURL: String, branch: String, sha: String,
        testLevel: ITRTestLevel, configurations: [String: String], customConfigurations: [String: String]
    ) throws(LibraryConfigurationCommunicationError) -> TracerSettings {
        try invoke(requestName: "SettingsRequest",
                   payload: "service: \(service), env: \(env)") { api throws(APICallError) in
            try await api.settings.tracerSettings(service: service, env: env,
                                                  repositoryURL: repositoryURL,
                                                  branch: branch, sha: sha,
                                                  testLevel: testLevel,
                                                  configurations: configurations,
                                                  customConfigurations: customConfigurations)
        }
    }

    /// Returns all known tests by fetching every page and merging results.
    public func knownTests(
        service: String, env: String, repositoryURL: String,
        configurations: [String: String], customConfigurations: [String: String]
    ) throws(LibraryConfigurationCommunicationError) -> KnownTestsMap {
        try invoke(requestName: "Known Tests Request",
                   payload: "service: \(service), env: \(env)") { api throws(APICallError) in
            try await api.knownTests.tests(service: service, env: env,
                                           repositoryURL: repositoryURL,
                                           configurations: configurations,
                                           customConfigurations: customConfigurations)
        }.tests
    }

    /// Returns a single page of known tests with pagination info when provided.
    public func knownTests(
        service: String, env: String, repositoryURL: String,
        configurations: [String: String], customConfigurations: [String: String],
        page: KnownTestsPageInfo
    ) throws(LibraryConfigurationCommunicationError) -> KnownTestsResult {
        try invoke(requestName: "Known Tests Request",
                   payload: "service: \(service), env: \(env)") { api throws(APICallError) in
            try await api.knownTests.tests(service: service, env: env,
                                           repositoryURL: repositoryURL,
                                           configurations: configurations,
                                           customConfigurations: customConfigurations,
                                           page: page)
        }
    }

    public func testManagementTests(
        repositoryURL: String, sha: String? = nil, commitMessage: String? = nil, module: String? = nil, branch: String? = nil
    ) throws(LibraryConfigurationCommunicationError) -> TestManagementTestsInfo {
        try invoke(requestName: "Test Management Tests Request",
                   payload: "repo: \(repositoryURL)") { api throws(APICallError) in
            try await api.testManagement.tests(repositoryURL: repositoryURL,
                                               sha: sha, commitMessage: commitMessage,
                                               branch: branch, module: module)
        }
    }

    public func shutdown(explicitTimeout: TimeInterval?) {
        _ = self.flush(explicitTimeout: explicitTimeout)
        logsExporter.shutdown()
        spansExporter.shutdown()
        coverageExporter.shutdown()
    }

    public var endpointURLs: Set<String> {
        var urls = Set<String>([
            configuration.endpoint.logsURL.absoluteString,
            configuration.endpoint.spansURL.absoluteString,
            configuration.endpoint.coverageURL.absoluteString,
        ])
        urls.formUnion(api.endpointURLs.map { $0.absoluteString })
        return urls
    }

    /// Drive an async API call from the synchronous public surface, mapping
    /// any `APICallError` into the public configuration-error shape with the
    /// request's name and payload summary.
    private func invoke<V>(
        requestName: String, payload: String,
        _ call: @Sendable @escaping (TestOptimizationApiService) async throws(APICallError) -> V
    ) throws(LibraryConfigurationCommunicationError) -> V {
        let api = self.api
        do {
            return try waitForAsync { () async throws(APICallError) -> V in
                try await call(api)
            }
        } catch let error {
            throw LibraryConfigurationCommunicationError(requestName: requestName,
                                                         payload: payload, error: error)
        }
    }
}
