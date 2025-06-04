/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import EventsExporter

final class TestManagement: TestHooksFeature {
    static var id: String = "Flaky Test Management"
    
    let modules: [String: Module]
    let attemptToFixRetries: UInt
    
    init(tests: TestManagementTestsInfo, attemptToFixRetries: UInt)
    {
        let mapped = tests.modules.map { ($0.key, Module(name: $0.key, module: $0.value)) }
        self.modules = Dictionary(uniqueKeysWithValues: mapped)
        self.attemptToFixRetries = attemptToFixRetries
    }
    
    func testSuiteWillStart(suite: any TestSuite, testsCount: UInt) {}
    
    func testGroupWillStart(for test: String, in suite: any TestSuite) {}
    
    func testGroupConfiguration(for test: String, meta: UnskippableMethodCheckerFactory, in suite: any TestSuite) -> TestRetryGroupConfiguration {
        .default
    }
    
    func testWillStart(test: any TestRun, retryReason: String?, skipStatus: SkipStatus,
                       executionCount: Int, failedExecutionCount: Int)
    {
    }
    
    func testWillFinish(test: any TestRun, duration: TimeInterval, withStatus: TestStatus,
                        skipStatus: SkipStatus, executionCount: Int, failedExecutionCount: Int) {}
    
    func testGroupRetry(test: any TestRun, duration: TimeInterval, withStatus: TestStatus,
                        skipStatus: SkipStatus, executionCount: Int, failedExecutionCount: Int) -> RetryStatus?
    {
        nil
    }
    
    func shouldSuppressError(test: any TestRun, skipStatus: SkipStatus, executionCount: Int, failedExecutionCount: Int) -> Bool {
        false
    }
    
    func stop() {}
}

extension TestManagement {
    struct Module {
        let name: String
        let suites: [String: Suite]
        
        init(name: String, module: TestManagementTestsInfo.Module) {
            let mapped = module.suites.map { ($0.key, Suite(name: $0.key, suite: $0.value)) }
            self.name = name
            self.suites = Dictionary(uniqueKeysWithValues: mapped)
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
    
    init(repository: String, commitMessage: String,
         attemptToFixRetries: UInt,
         exporter: EventsExporterProtocol, cache: Directory
    ) {
        self.cacheFolder = cache
        self.repository = repository
        self.commitMessage = commitMessage
        self.attemptToFixRetries = attemptToFixRetries
        self.exporter = exporter
    }
    
    static func isEnabled(config: Config, env: Environment, remote: TracerSettings) -> Bool {
        remote.testManagement.enabled && config.testManagementEnabled
    }
    
    func create(log: Logger) -> TestManagement? {
        if let tests = loadTestsFromDisk(log: log) {
            log.debug("Test Management Enabled")
            return TestManagement(tests: tests, attemptToFixRetries: attemptToFixRetries)
        }
        guard let tests = getTests(exporter: exporter, log: log) else {
            return nil
        }
        saveTests(tests: tests)
        log.debug("Test Management Enabled")
        return TestManagement(tests: tests, attemptToFixRetries: attemptToFixRetries)
    }
    
    private func loadTestsFromDisk(log: Logger) -> TestManagementTestsInfo? {
        guard cacheFolder.hasFile(named: cacheFileName) else { return nil }
        guard let data = try? cacheFolder.file(named: cacheFileName).read() else {
            log.print("Test Management: Can't read \(cacheFileName) from \(cacheFolder)")
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
        let tests = exporter.testManagementTests(repositoryURL: repository, commitMessage: commitMessage, module: nil)
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
            let testsFile = try? cacheFolder.createFile(named: cacheFileName)
            try? testsFile?.append(data: data)
        }
    }
}
