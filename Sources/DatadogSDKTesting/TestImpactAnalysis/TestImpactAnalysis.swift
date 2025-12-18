/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

final class TestImpactAnalysis: TestHooksFeature {
    static var id: FeatureId = "Test Impact Analysis"
    
    let modules: [String: [String: Suite]]
    let correlationId: String?
    let coverage: TestCoverageCollector?
    
    var skippedCount: UInt { _skippedCount.value }
    
    var isSkippingEnabled: Bool { correlationId != nil }
    var isCoverageEnabled: Bool { coverage != nil }
    
    private var _skippedCount: Synced<UInt>
    
    private(set) var unskippableCache: Synced<[ObjectIdentifier: UnskippableMethodChecker]>
    
    init(tests: SkipTests?, coverage: TestCoverageCollector?) {
        if let tests = tests { // we have skipping enabled
            var modules = [String: [String: Suite]]()
            for test in tests.tests {
                guard let moduleName = test.module else { continue }
                modules.get(key: moduleName, or: [:]) { module in
                    module.get(key: test.suite, or: Suite(name: test.suite, methods: [:])) { suite in
                        suite.methods.get(key: test.name, or: Test(name: test.name, configurations: [])) {
                            $0.configurations.append(Configuration(standard: test.configurations,
                                                                   custom: test.customConfigurations))
                        }
                    }
                }
            }
            self.modules = modules
            self.correlationId = tests.correlationId
        } else { // we will only try to gather code coverage
            self.modules = [:]
            self.correlationId = nil
        }
        self.unskippableCache = .init([:])
        self._skippedCount = .init(0)
        self.coverage = coverage
    }
    
    func status(for clazz: UnskippableMethodCheckerFactory, named test: String, suite: String, module: String) -> SkipStatus {
        let checker = unskippableCache.update { cache in
            cache.get(key: clazz.classId, or: clazz.unskippableMethods)
        }
        return .init(canBeSkipped: modules[module]?[suite]?[test] != nil,
                     markedUnskippable: !checker.canSkip(method: test))
    }
    
    func testGroupConfiguration(for test: String, meta: UnskippableMethodCheckerFactory,
                                in suite: any TestSuite,
                                configuration: RetryGroupConfiguration.Iterator) -> RetryGroupConfiguration.Iterator
    {
        let status = status(for: meta, named: test, suite: suite.name, module: suite.module.name)
        if status.markedUnskippable {
            suite.set(tag: DDItrTags.itrUnskippable, value: true)
        }
        // we can't skip it so do nothing
        guard status.canBeSkipped else { return configuration.next() }
        // if it's skipped we skip it, else simply add info to the configuration
        return status.isSkipped
            ? configuration.skip(reason: "Skipped by Test Impact Analysis",
                                 status: status,
                                 strategy: .allSkipped)
            : configuration.next(skipStatus: status,
                                 skipStrategy: .atLeastOneSkipped)
    }
    
    func testWillStart(test: any TestRun, info: TestRunInfoStart) {
        if let correlationId = correlationId {
            test.set(tag: DDItrTags.itrCorrelationId, value: correlationId)
        }
        if info.skip.status.markedUnskippable {
            test.set(tag: DDItrTags.itrUnskippable, value: "true")
        }
        if !info.skip.status.isSkipped {
            coverage?.startTest()
        }
    }
    
    func testWillFinish(test: any TestRun, duration: TimeInterval, withStatus status: TestStatus, andInfo info: TestRunInfoEnd) {
        switch status {
        case .pass, .fail:
            if info.skip.status.isForcedRun {
                test.set(tag: DDItrTags.itrForcedRun, value: "true")
            }
        case .skip:
            if info.skip.by?.feature == id && info.skip.status.isSkipped {
                test.set(tag: DDTestTags.testSkippedByITR, value: "true")
                _skippedCount.update { $0 += 1 }
            }
        }
    }
    
    func testDidFinish(test: any TestRun, info: TestRunInfoEnd) {
        if !info.skip.status.isSkipped {
            coverage?.endTest(testSessionId: test.session.id.rawValue,
                              testSuiteId: test.suite.id.rawValue,
                              spanId: test.id.rawValue)
        }
    }
    
    func testGroupRetry(test: any TestRun, duration: TimeInterval,
                        withStatus: TestStatus, retryStatus: RetryStatus.Iterator,
                        andInfo info: TestRunInfoStart) -> RetryStatus.Iterator
    {
        // we have to return end value so test will not be passed for retry to other features
        info.skip.status.isSkipped ? retryStatus.end() : retryStatus.next()
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
    let environment: String
    let service: String
    let api: TestImpactAnalysisApi
    let skippingEnabled: Bool
    let coverageConfig: Coverage?
    
    init(configurations: [String: String],
         custom: [String: String],
         api: TestImpactAnalysisApi,
         commit: String, repository: String,
         environment: String, service: String,
         cache: Directory, skippingEnabled: Bool,
         coverage: Coverage?)
    {
        self.configurations = configurations
        self.customConfigurations = custom
        self.cacheFolder = cache
        self.api = api
        self.repository = repository
        self.commitSha = commit
        self.environment = environment
        self.service = service
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
    
    func create(log: Logger) -> AsyncResult<FT, any Error> {
        guard skippingEnabled else {
            return create(log: log, tests: nil)
        }
        if let tests = loadTestsFromDisk(log: log) {
            return create(log: log, tests: tests)
        }
        return api.skippableTests(repositoryURL: repository.spanAttribute,
                           sha: commitSha, environment: environment, service: service,
                           tiaLevel: .test, configurations: configurations,
                           customConfigurations: customConfigurations)
        .mapError { $0 as (any Error) }
        .flatMap { tests in
            log.debug("TIA tests: \(tests)")
            self.saveTests(tests: tests)
            return self.create(log: log, tests: tests)
        }
    }
    
    private func create(log: Logger, tests: SkipTests?) -> AsyncResult<FT, any Error> {
        let coverage = coverageConfig.flatMap { config in
            DDCoverageHelper(storagePath: config.tempFolder,
                             exporter: config.exporter,
                             workspacePath: config.workspacePath,
                             priority: config.priority,
                             debug: config.debug)
        }
        log.debug("Test Impact Analysis Enabled")
        if coverage != nil {
            log.debug("Code Coverage Enabled")
        }
        return .value(TestImpactAnalysis(tests: tests, coverage: coverage))
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
        let exporter: CoverageExporterType
    }
}
