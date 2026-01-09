/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk
import CodeCoverageParser

public protocol EventsExporterProtocol {
    var configuration: ExporterConfiguration { get }
    var coverageExporter: CoverageExporterType { get }
    var spansExporter: SpansExporterType { get }
    var logsExporter: LogsExporterType { get }
    
    func setMetadata(_ metadata: SpanMetadata)
    func flush(explicitTimeout: TimeInterval?) -> ExportResult
    func shutdown(explicitTimeout: TimeInterval?)
}

extension EventsExporterProtocol {
    public func flush() -> ExportResult {
        flush(explicitTimeout: nil)
    }
    
    public func shutdown() {
        shutdown(explicitTimeout: nil)
    }
}

public class EventsExporter: EventsExporterProtocol {
    public let configuration: ExporterConfiguration
    public private(set) var spansExporter: SpansExporterType
    public private(set) var logsExporter: LogsExporterType
    public private(set) var coverageExporter: CoverageExporterType

    public init(config: ExporterConfiguration, api: TestOpmimizationApi) throws {
        self.configuration = config
        Log.setLogger(config.logger)
        logsExporter = try LogsExporter(config: configuration, api: api.logs)
        
        let spans = try SpansExporter(config: configuration, api: api.spans)
        spansExporter = MultiSpanExporter(spanExporters: [spans, SpanEventsLogExporterAdapter(logsExporter: logsExporter)])
        
        coverageExporter = try CoverageExporter(config: configuration, api: api.tia)
        config.logger.debug("EventsExporter created: \(config.exporterId), endpoint: \(api.endpoint)")
    }

//    public func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
//        // TODO: Honor the timeout
//        spans.forEach {
//            if $0.traceFlags.sampled {
//                spansExporter.exportSpan(span: $0)
//            }
//            if $0.traceFlags.sampled {
//                logsExporter.exportLogs(fromSpan: $0)
//            }
//        }
//        return .success
//    }
    
    public func setMetadata(_ metadata: SpanMetadata) {
        spansExporter.setMetadata(metadata)
    }

//    public func exportEvent<T: Encodable>(event: T) {
//        if configuration.performancePreset.synchronousWrite {
//            spansExporter.spansStorage.writer.writeSync(value: event)
//        } else {
//            spansExporter.spansStorage.writer.write(value: event)
//        }
//    }

    public func flush(explicitTimeout: TimeInterval?) -> ExportResult {
        let spans = spansExporter.flush(explicitTimeout: explicitTimeout)
        let logs = logsExporter.forceFlush(explicitTimeout: explicitTimeout)
        let coverage = coverageExporter.forceFlush(explicitTimeout: explicitTimeout)
        return spans && logs && coverage ? .success : .failure
    }

//    public func export(coverage: URL, parser: CoverageParser, workspacePath: String?,
//                       testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64)
//    {
//        coverageExporter.exportCoverage(coverage: coverage, parser: parser, workspacePath: workspacePath,
//                                        testSessionId: testSessionId, testSuiteId: testSuiteId, spanId: spanId)
//    }
//
//    public func searchCommits(repositoryURL: String, commits: [String]) -> [String] {
//        return itrService.searchExistingCommits(repositoryURL: repositoryURL, commits: commits)
//    }
//
//    public func uploadPackFiles(packFilesDirectory: Directory, commit: String, repository: String) throws {
//        try itrService.uploadPackFiles(packFilesDirectory: packFilesDirectory, commit: commit, repository: repository)
//    }
//
//    public func skippableTests(
//        repositoryURL: String, sha: String, testLevel: ITRTestLevel,
//        configurations: [String: String], customConfigurations: [String: String]) -> SkipTests?
//    {
//        itrService.skippableTests(repositoryURL: repositoryURL, sha: sha,
//                                  testLevel: testLevel,
//                                  configurations: configurations,
//                                  customConfigurations: customConfigurations)
//    }
//
//    public func tracerSettings(
//        service: String, env: String, repositoryURL: String, branch: String, sha: String,
//        testLevel: ITRTestLevel, configurations: [String: String], customConfigurations: [String: String]
//    ) -> TracerSettings? {
//        settingsService.settings(
//            service: service, env: env, repositoryURL: repositoryURL,
//            branch: branch, sha: sha, testLevel: testLevel, configurations: configurations,
//            customConfigurations: customConfigurations
//        )
//    }
//    
//    public func knownTests(
//        service: String, env: String, repositoryURL: String,
//        configurations: [String: String], customConfigurations: [String: String]
//    ) -> KnownTestsMap? {
//        knownTestsService.tests(service: service, env: env, repositoryURL: repositoryURL,
//                                configurations: configurations, customConfigurations: customConfigurations)
//    }
//    
//    public func testManagementTests(
//        repositoryURL: String, sha: String? = nil, commitMessage: String? = nil, module: String? = nil, branch: String? = nil
//    ) -> TestManagementTestsInfo? {
//        testManagementService.tests(repositoryURL: repositoryURL, sha: sha, commitMessage: commitMessage, module: module, branch: branch)
//    }

    public func shutdown(explicitTimeout: TimeInterval?) {
        spansExporter.shutdown(explicitTimeout: explicitTimeout)
        logsExporter.shutdown(explicitTimeout: explicitTimeout)
        coverageExporter.shutdown(explicitTimeout: explicitTimeout)
    }
}
