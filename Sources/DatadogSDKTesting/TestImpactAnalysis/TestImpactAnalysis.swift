/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

final class TestImpactAnalysis: TestHooksFeature {
    static var id: String = "Test Impact Analysis"
    
    let suites: [String: Suite]
    let correlationId: String?
    let coverage: TestCoverageCollector?
    
    var skippedCount: UInt { _skippedCount.value }
    
    var isSkippingEnabled: Bool { correlationId != nil }
    var isCoverageEnabled: Bool { coverage != nil }
    
    private var _skippedCount: Synced<UInt>
    
    private(set) var unskippableCache: Synced<[ObjectIdentifier: UnskippableMethodChecker]>
    
    init(tests: SkipTests?, coverage: TestCoverageCollector?) {
        if let tests = tests { // we have skipping enabled
            var suites = [String: Suite]()
            for test in tests.tests {
                suites.get(key: test.suite, or: Suite(name: test.suite, methods: [:])) { suite in
                    suite.methods.get(key: test.name, or: Test(name: test.name, configurations: [])) {
                        $0.configurations.append(Configuration(standard: test.configuration, custom: test.customConfiguration))
                    }
                }
            }
            self.suites = suites
            self.correlationId = tests.correlationId
        } else { // we will only try to gather code coverage
            self.suites = [:]
            self.correlationId = nil
        }
        self.unskippableCache = .init([:])
        self._skippedCount = .init(0)
        self.coverage = coverage
    }
    
    func status(for clazz: UnskippableMethodCheckerFactory, named test: String, in suite: String) -> SkipStatus {
        let checker = unskippableCache.update { cache in
            cache.get(key: clazz.classId, or: clazz.unskippableMethods)
        }
        return .init(canBeSkipped: suites[suite]?[test] != nil,
                     markedUnskippable: !checker.canSkip(method: test))
    }
    
    func testGroupConfiguration(for test: String, meta: UnskippableMethodCheckerFactory,
                                in suite: any TestSuite,
                                configuration: TestRetryGroupConfiguration.Configuration) -> TestRetryGroupConfiguration
    {
        let status = status(for: meta, named: test, in: suite.name)
        if status.markedUnskippable {
            suite.set(tag: DDItrTags.itrUnskippable, value: true)
        }
        // we can't skip it so do nothing
        guard status.canBeSkipped else { return configuration.next() }
        // if it's skipped we skip it, else simply add info to the configuration
        return status.isSkipped
            ? configuration.skip(status: status, strategy: .allSkipped)
            : configuration.next(skipStatus: status, skipStrategy: .atLeastOneSkipped)
    }
    
    func testWillStart(test: any TestRun, retryReason: String?, skipStatus: SkipStatus, executionCount: Int, failedExecutionCount: Int) {
        if let correlationId = correlationId {
            test.set(tag: DDItrTags.itrCorrelationId, value: correlationId)
        }
        if skipStatus.markedUnskippable {
            test.set(tag: DDItrTags.itrUnskippable, value: "true")
        }
        if !skipStatus.isSkipped {
            coverage?.startTest()
        }
    }
    
    func testWillFinish(test: any TestRun, duration: TimeInterval, withStatus status: TestStatus,
                        skipStatus: SkipStatus, executionCount: Int, failedExecutionCount: Int)
    {
        switch status {
        case .pass, .fail:
            if skipStatus.isForcedRun {
                test.set(tag: DDItrTags.itrForcedRun, value: "true")
            }
        case .skip:
            if skipStatus.isSkipped {
                test.set(tag: DDTestTags.testSkippedByITR, value: "true")
                _skippedCount.update { $0 += 1 }
            }
        }

        if !skipStatus.isSkipped {
            coverage?.endTest(testSessionId: test.session.id.rawValue,
                              testSuiteId: test.suite.id.rawValue,
                              spanId: test.id.rawValue)
        }
    }
    
    func testGroupRetry(test: any TestRun, duration: TimeInterval,
                        withStatus: TestStatus, skipStatus: SkipStatus,
                        executionCount: Int, failedExecutionCount: Int) -> RetryStatus?
    {
        // we have to return value so test will not be passed for retry to other features
        // it will record errors if needed (which should not happen)
        skipStatus.isSkipped ? .recordErrors : nil
    }
    
    func stop() {
        coverage?.stop()
    }
}

extension TestImpactAnalysis {
    struct Configuration {
        let standard: [String: String]?
        let custom: [String: String]?
    }
    
    struct Test {
        let name: String
        var configurations: [Configuration]
    }
    
    struct Suite {
        let name: String
        var methods: [String: Test]
        
        subscript(_ method: String) -> Test? { methods[method] }
    }
}

struct TestImpactAnalysisFactory: FeatureFactory {
    typealias FT = TestImpactAnalysis
    
    private let cacheFileName = "skippable_tests.json"
    let configurations: [String: String]
    let customConfigurations: [String: String]
    let cacheFolder: Directory
    let commitSha: String
    let repository: String
    let exporter: EventsExporterProtocol
    let skippingEnabled: Bool
    let coverageConfig: Coverage?
    
    init(configurations: [String: String],
         custom: [String: String],
         exporter: EventsExporterProtocol,
         commit: String, repository: String,
         cache: Directory, skippingEnabled: Bool,
         coverage: Coverage?)
    {
        self.configurations = configurations
        self.customConfigurations = custom
        self.cacheFolder = cache
        self.exporter = exporter
        self.repository = repository
        self.commitSha = commit
        self.coverageConfig = coverage
        self.skippingEnabled = skippingEnabled
    }
    
    static func isEnabled(config: Config, env: Environment, remote: TracerSettings) -> Bool {
        guard config.itrEnabled && remote.itr.itrEnabled else { return false }
        
        let isExcluded = { (branch: String) in
            let excludedBranches = config.excludedBranches
            if excludedBranches.contains(branch) {
                Log.debug("Excluded branch: \(branch)")
                return true
            }
            let match = excludedBranches
                .filter { $0.hasSuffix("*") }
                .map { $0.dropLast() }
                .first { branch.hasPrefix($0) }
            if let wildcard = match {
                Log.debug("Excluded branch: \(branch) with wildcard: \(wildcard)*")
                return true
            }
            return false
        }
        
        guard let branch = DDTestMonitor.env.git.branch else {
            return false
        }
        
        return !isExcluded(branch)
    }
    
    func create(log: Logger) -> TestImpactAnalysis? {
        guard skippingEnabled else {
            return create(log: log, tests: nil)
        }
        if let tests = loadTestsFromDisk(log: log) {
            return create(log: log, tests: tests)
        }
        guard let tests = getTests(exporter: exporter, log: log) else {
            return nil
        }
        saveTests(tests: tests)
        return create(log: log, tests: tests)
    }
    
    private func create(log: Logger, tests: SkipTests?) -> TestImpactAnalysis {
        let coverage = coverageConfig.flatMap { config in
            DDCoverageHelper(storagePath: config.tempFolder,
                             exporter: exporter,
                             workspacePath: config.workspacePath,
                             priority: config.priority,
                             debug: config.debug)
        }
        log.debug("Test Impact Analysis Enabled")
        if coverage != nil {
            log.debug("Code Coverage Enabled")
        }
        return TestImpactAnalysis(tests: tests, coverage: coverage)
    }
    
    private func loadTestsFromDisk(log: Logger) -> SkipTests? {
        guard cacheFolder.hasFile(named: cacheFileName) else { return nil }
        guard let data = try? cacheFolder.file(named: cacheFileName).read() else {
            log.print("TIA: Can't read \(cacheFileName) from \(cacheFolder)")
            return nil
        }
        do {
            let tests = try JSONDecoder().decode(SkipTests.self, from: data)
            log.debug("TIA: loaded tests: \(tests)")
            return tests
        } catch {
            log.print("TIA: Can't decode tests data: \(error)")
            return nil
        }
    }
    
    private func getTests(exporter: EventsExporterProtocol, log: Logger) -> SkipTests? {
        let tests = exporter.skippableTests(
            repositoryURL: repository.spanAttribute, sha: commitSha, testLevel: .test,
            configurations: configurations, customConfigurations: customConfigurations
        )
        guard let tests = tests else {
            Log.print("TIA: tests request failed")
            return nil
        }
        Log.debug("TIA: tests: \(tests)")
        return tests
    }
    
    private func saveTests(tests: SkipTests) {
        if let data = try? JSONEncoder().encode(tests) {
            let testsFile = try? cacheFolder.createFile(named: cacheFileName)
            try? testsFile?.append(data: data)
        }
    }
    
}

extension TestImpactAnalysisFactory {
    struct Coverage {
        let workspacePath: String?
        let priority: CodeCoveragePriority
        let tempFolder: Directory
        let debug: Bool
    }
}
