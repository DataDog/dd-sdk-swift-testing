/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

final class TestManagement: TestHooksFeature {
    static var id: String = "Flaky Test Management"
    
    let module: Module
    let attemptToFixRetries: UInt
    
    init(tests: TestManagementTestsInfo, attemptToFixRetries: UInt, module: String)
    {
        let mapped = tests.modules.map { ($0.key, Module(name: $0.key, module: $0.value)) }
        let modules = Dictionary(uniqueKeysWithValues: mapped)
        self.module = modules[module] ?? Module(name: module, suites: [:])
        self.attemptToFixRetries = attemptToFixRetries
    }
    
    func testSuiteWillStart(suite: any TestSuite, testsCount: UInt) {}
    
    func testGroupWillStart(for test: String, in suite: any TestSuite) {}
    
    func testGroupConfiguration(for test: String, meta: UnskippableMethodCheckerFactory,
                                in suite: any TestSuite,
                                configuration: TestRetryGroupConfiguration.Configuration) -> TestRetryGroupConfiguration
    {
        guard let testInfo = module.suites[suite.name]?.tests[test] else {
            return configuration.next()
        }
        if testInfo.attemptToFix {
            let strategy: RetryGroupSuccessStrategy = testInfo.disabled || testInfo.quarantined ?
                .alwaysSucceeded : .allSucceeded
            return configuration.retry(strategy: strategy)
        }
        if testInfo.disabled {
            return configuration.skip(status: .init(canBeSkipped: true, markedUnskippable: false), strategy: .allSkipped)
        }
        if testInfo.quarantined {
            // Do nothing by add success strategy
            return configuration.next(successStrategy: .alwaysSucceeded)
        }
        // Do nothing.
        return configuration.next()
    }
    
    func testWillStart(test: any TestRun, info: TestRunInfo) {
        guard info.retry?.reason == id else { return }
        test.set(tag: DDEfdTags.testIsRetry, value: "true")
        test.set(tag: DDEfdTags.testRetryReason, value: DDTagValues.retryReasonAttemptToFix)
    }
    
    func testWillFinish(test: any TestRun, duration: TimeInterval, withStatus status: TestStatus, andInfo info: TestRunInfo) {
        guard info.retry?.reason == id else { return } // Check that was retied by us
        guard info.retry?.status != .retry else { return } // last execution.
        if info.executions.failed >= info.executions.total { // all executions failed
            test.set(tag: DDTestTags.testHasFailedAllRetries, value: "true")
        }
        // Check that all executions passed
        test.set(tag: DDTestManagementTags.testAttemptToFixPassed,
                 value: info.executions.failed == 0)
    }
    
    func testGroupRetry(test: any TestRun, duration: TimeInterval, withStatus status: TestStatus,
                        andInfo info: TestRunInfo) -> RetryStatus?
    {
        guard let testInfo = module.suites[test.suite.name]?.tests[test.name] else {
            return nil
        }
        if testInfo.attemptToFix {
            if info.executions.total < attemptToFixRetries - 1 {
                return .retry
            }
            return testInfo.disabled || testInfo.quarantined ? .pass : .recordErrors
        }
        return testInfo.disabled || testInfo.quarantined  ? .pass : nil
    }
    
    func shouldSuppressError(test: any TestRun, info: TestRunInfo) -> Bool {
        guard let testInfo = module.suites[test.suite.name]?.tests[test.name] else {
            return false
        }
        return testInfo.disabled || testInfo.quarantined || ( // disabled or quarantined
            testInfo.attemptToFix && info.executions.total < attemptToFixRetries
        )
    }
    
    func stop() {}
}

extension TestManagement {
    struct Module {
        let name: String
        let suites: [String: Suite]
        
        init(name: String, suites: [String: Suite]) {
            self.name = name
            self.suites = suites
        }
        
        init(name: String, module: TestManagementTestsInfo.Module) {
            let mapped = module.suites.map { ($0.key, Suite(name: $0.key, suite: $0.value)) }
            self.init(name: name, suites: Dictionary(uniqueKeysWithValues: mapped))
        }
    }
    
    struct Suite {
        let name: String
        let tests: [String: Test]
        
        init(name: String, suite: TestManagementTestsInfo.Suite) {
            let mapped = suite.tests.map { ($0.key, Test(name: $0.key, test: $0.value)) }
            self.name = name
            self.tests = Dictionary(uniqueKeysWithValues: mapped)
        }
    }
    
    struct Test {
        let name: String
        let disabled: Bool
        let quarantined: Bool
        let attemptToFix: Bool
        
        init(name: String, test: TestManagementTestsInfo.Test) {
            self.name = name
            self.disabled = test.properties.disabled
            self.quarantined = test.properties.quarantined
            self.attemptToFix = test.properties.attemptToFix
        }
    }
}

struct TestManagementFactory: FeatureFactory {
    typealias FT = TestManagement
    
    let cacheFileName = "test_management_tests.json"
    let repository: String
    let commitMessage: String
    let attemptToFixRetries: UInt
    let cacheFolder: Directory
    let exporter: EventsExporterProtocol
    let module: String
    
    init(repository: String, commitMessage: String,
         module: String, attemptToFixRetries: UInt,
         exporter: EventsExporterProtocol, cache: Directory
    ) {
        self.cacheFolder = cache
        self.repository = repository
        self.commitMessage = commitMessage
        self.attemptToFixRetries = attemptToFixRetries
        self.exporter = exporter
        self.module = module
    }
    
    static func isEnabled(config: Config, env: Environment, remote: TracerSettings) -> Bool {
        remote.testManagement.enabled && config.testManagementEnabled
    }
    
    func create(log: Logger) -> TestManagement? {
        if let tests = loadTestsFromDisk(log: log) {
            log.debug("Test Management Enabled")
            return TestManagement(tests: tests, attemptToFixRetries: attemptToFixRetries, module: module)
        }
        guard let tests = getTests(exporter: exporter, log: log) else {
            return nil
        }
        saveTests(tests: tests)
        log.debug("Test Management Enabled")
        return TestManagement(tests: tests, attemptToFixRetries: attemptToFixRetries, module: module)
    }
    
    private func loadTestsFromDisk(log: Logger) -> TestManagementTestsInfo? {
        let fileName = "\(module)_\(cacheFileName)"
        guard cacheFolder.hasFile(named: fileName) else { return nil }
        guard let data = try? cacheFolder.file(named: fileName).read() else {
            log.print("Test Management: Can't read \(fileName) from \(cacheFolder)")
            return nil
        }
        do {
            let tests = try JSONDecoder().decode(TestManagementTestsInfo.self, from: data)
            log.debug("Test Management: loaded tests: \(tests)")
            return tests
        } catch {
            log.print("Test Management: Can't decode tests data: \(error)")
            return nil
        }
    }
    
    private func getTests(exporter: EventsExporterProtocol, log: Logger) -> TestManagementTestsInfo? {
        let tests = exporter.testManagementTests(repositoryURL: repository, commitMessage: commitMessage, module: module)
        guard let tests = tests else {
            Log.print("Test Management: tests request failed")
            return nil
        }
        Log.debug("Test Management: tests: \(tests)")
        // if we have empty array we can disable Test Management functionality
        guard tests.modules.count > 0 else { return nil }
        return tests
    }
    
    private func saveTests(tests: TestManagementTestsInfo) {
        if let data = try? JSONEncoder().encode(tests) {
            let testsFile = try? cacheFolder.createFile(named: "\(module)_\(cacheFileName)")
            try? testsFile?.append(data: data)
        }
    }
}
