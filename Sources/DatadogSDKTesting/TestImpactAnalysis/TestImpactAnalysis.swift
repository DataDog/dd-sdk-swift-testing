/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import OpenTelemetryApi
internal import EventsExporter

final class TestImpactAnalysis: TestHooksFeature {
    static var id: FeatureId = "Test Impact Analysis"

    let modules: [String: [String: Suite]]
    let correlationId: String?
    let swiftTestingEnabled: Bool

    var skippedCount: UInt { _skippedCount.value }

    var isSkippingEnabled: Bool { correlationId != nil }

    private let _skippedCount: Synced<UInt>

    init(tests: SkipTests?, swiftTestingEnabled: Bool) {
        if let tests = tests { // we have skipping enabled
            var modules = [String: [String: Suite]]()
            for test in tests.tests {
                guard let moduleName = test.configuration?["test.bundle"] else { continue }
                modules.get(key: moduleName, or: [:]) { module in
                    module.get(key: test.suite, or: Suite(name: test.suite, methods: [:])) { suite in
                        suite.methods.get(key: test.name, or: Test(name: test.name, configurations: [])) {
                            $0.configurations.append(Configuration(standard: test.configuration,
                                                                   custom: test.customConfiguration))
                        }
                    }
                }
            }
            self.modules = modules
            self.correlationId = tests.correlationId
        } else {
            self.modules = [:]
            self.correlationId = nil
        }
        self.swiftTestingEnabled = swiftTestingEnabled
        self._skippedCount = .init(0)
    }

    func status(named test: String, suite: String, module: String, skippable: Bool) -> SkipStatus {
        return .init(canBeSkipped: modules[module]?[suite]?[test] != nil,
                     markedUnskippable: !skippable)
    }

    func testSessionWillEnd(session: any TestSession) {
        session.set(tag: DDTestSessionTags.testSkippingEnabled, value: isSkippingEnabled)
        if isSkippingEnabled {
            let itrSkipped = skippedCount
            session.set(tag: DDTestSessionTags.testItrSkippingType, value: DDTagValues.typeTest)
            session.set(tag: DDItrTags.itrSkippedTests, value: itrSkipped > 0)
            session.set(tag: DDTestSessionTags.testItrSkipped, value: itrSkipped > 0)
            session.set(metric: DDTestSessionTags.testItrSkippingCount, value: Double(itrSkipped))
        }
    }

    func testModuleWillEnd(module: any TestModule) {
        module.set(tag: DDTestSessionTags.testSkippingEnabled, value: isSkippingEnabled)
        if isSkippingEnabled {
            let itrSkipped = skippedCount
            module.set(tag: DDTestSessionTags.testItrSkippingType, value: DDTagValues.typeTest)
            module.set(tag: DDItrTags.itrSkippedTests, value: itrSkipped > 0)
            module.set(tag: DDTestSessionTags.testItrSkipped, value: itrSkipped > 0)
            module.set(metric: DDTestSessionTags.testItrSkippingCount, value: Double(itrSkipped))
        }
    }

    func testSuiteWillEnd(suite: any TestSuite) {
        guard !suite.isSwiftTesting || swiftTestingEnabled else {
            return
        }
        suite.set(tag: DDTestSessionTags.testSkippingEnabled, value: isSkippingEnabled)
    }
    
    func testGroupConfiguration(for test: String, tags: any TestTags,
                                in suite: any TestSuite,
                                configuration: RetryGroupConfiguration.Iterator) -> RetryGroupConfiguration.Iterator
    {
        guard !suite.isSwiftTesting || swiftTestingEnabled else {
            return configuration.next()
        }
        let status = status(named: test, suite: suite.name, module: suite.module.name,
                            skippable: tags.get(tag: .tiaSkippable) ?? true)
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
        guard !test.suite.isSwiftTesting || swiftTestingEnabled else {
            return
        }
        test.set(tag: DDTestSessionTags.testSkippingEnabled, value: isSkippingEnabled)
        if let correlationId = correlationId {
            test.set(tag: DDItrTags.itrCorrelationId, value: correlationId)
        }
        if info.skip.status.markedUnskippable {
            test.set(tag: DDItrTags.itrUnskippable, value: "true")
        }
    }
    
    func testWillFinish(test: any TestRun, duration: TimeInterval, withStatus status: TestStatus, andInfo info: TestRunInfoEnd) {
        guard !test.suite.isSwiftTesting || swiftTestingEnabled else {
            return
        }
        switch status {
        case .pass, .fail:
            if info.skip.status.isForcedRun {
                test.set(tag: DDItrTags.itrForcedRun, value: "true")
            }
        case .skip:
            if info.skip.by?.feature == id && info.skip.status.isSkipped {
                test.set(tag: DDTestTags.testSkippedByITR, value: "true")
                test.set(tag: DDTestTags.testFinalStatus, value: TestStatus.skip)
                _skippedCount.update { $0 += 1 }
            }
        }
    }
    
    func testGroupRetry(test: any TestRun, duration: TimeInterval,
                        withStatus: TestStatus, retryStatus: RetryStatus.Iterator,
                        andInfo info: TestRunInfoStart) -> RetryStatus.Iterator
    {
        guard !test.suite.isSwiftTesting || swiftTestingEnabled else {
            return retryStatus.next()
        }
        guard info.skip.by?.feature == id else {
            return retryStatus.next()
        }
        // we have to return end value so test will not be passed for retry to other features
        return info.skip.status.isSkipped ? retryStatus.end() : retryStatus.next()
    }

    func stop() {}
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
    let service: String
    let environment: String
    let api: TestImpactAnalysisApi
    let skippingEnabled: Bool
    let swiftTestingEnabled: Bool

    init(configurations: [String: String],
         custom: [String: String],
         api: TestImpactAnalysisApi,
         service: String, environment: String,
         commit: String, repository: String,
         cache: Directory, skippingEnabled: Bool,
         swiftTestingEnabled: Bool)
    {
        self.configurations = configurations
        self.customConfigurations = custom
        self.cacheFolder = cache
        self.api = api
        self.service = service
        self.environment = environment
        self.repository = repository
        self.commitSha = commit
        self.skippingEnabled = skippingEnabled
        self.swiftTestingEnabled = swiftTestingEnabled
    }

    static func isEnabled(config: Config, env: Environment, remote: TracerSettings) -> Bool {
        guard config.tiaEnabled && remote.itr.itrEnabled else { return false }

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

    func create(log: Logger) async throws -> TestImpactAnalysis {
        guard skippingEnabled else {
            return create(log: log, tests: nil)
        }
        if let tests = loadTestsFromDisk(log: log) {
            return create(log: log, tests: tests)
        }
        let tests = try await fetchTests()
        saveTests(tests: tests)
        return create(log: log, tests: tests)
    }

    private func create(log: Logger, tests: SkipTests?) -> TestImpactAnalysis {
        log.debug("Test Impact Analysis Enabled")
        return TestImpactAnalysis(tests: tests, swiftTestingEnabled: swiftTestingEnabled)
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

    private func fetchTests() async throws -> SkipTests {
        do {
            return try await api.skippableTests(repositoryURL: repository.spanAttribute,
                                                sha: commitSha,
                                                environment: environment, service: service,
                                                testLevel: .test,
                                                configurations: configurations,
                                                customConfigurations: customConfigurations)
        } catch {
            throw LibraryConfigurationCommunicationError(
                requestName: "SkipTestsRequest",
                payload: "sha: \(commitSha)",
                error: error
            )
        }
    }

    private func saveTests(tests: SkipTests) {
        if let data = try? JSONEncoder().encode(tests) {
            let testsFile = try? cacheFolder.createFile(named: cacheFileName)
            try? testsFile?.append(data: data)
        }
    }
}

