/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

final class EarlyFlakeDetection: TestHooksFeature {
    static var id: String = "Early Flake Detection"
    
    let knownTests: KnownTests
    let knownTestsCount: Double
    let slowTestRetries: TracerSettings.EFD.TimeTable
    let faultySessionThreshold: Double
    private(set) var sessionFailed: Bool
    
    let log: Logger
    private var _counters: Synced<Counters>
    
    var testCounters: Counters { _counters.value }
    
    init(knownTests: KnownTests,
         slowTestRetries: TracerSettings.EFD.TimeTable,
         faultySessionThreshold: Double,
         log: Logger
    ) {
        self.knownTests = knownTests
        self.slowTestRetries = slowTestRetries
        self.faultySessionThreshold = faultySessionThreshold
        let count = knownTests.modules.values.reduce(0) { acc, suite in
            acc + suite.suites.values.reduce(0) { $0 + $1.tests.count }
        }
        self.knownTestsCount = Double(count)
        self.sessionFailed = false
        self._counters = Synced(.init())
        self.log = log
    }
    
    private func checkStatus(for test: any TestRun) -> Bool {
        checkStatus(for: test.name, in: test.suite)
    }
    
    private func checkStatus(for test: String, in suite: any TestSuite) -> Bool {
        // Calculate threshold
        let isNotFailed = _counters.use { counts in
            guard !self.sessionFailed else { return false }
            let testsCount = max(self.knownTestsCount, Double(counts.knownTests))
            let newTests = Double(counts.newTests)
            guard newTests <= self.faultySessionThreshold || ((newTests / testsCount) * 100.0) < self.faultySessionThreshold else {
                self.log.print("Early Flake Detection Faulty Session detected!")
                self.sessionFailed = true
                return false
            }
            return true
        }
        return isNotFailed && knownTests.isNew(test: test, in: suite.name, and: suite.module.name)
    }
    
    func testSuiteWillStart(suite: any TestSuite, testsCount: UInt) {
        _counters.update { $0.knownTests += testsCount }
    }
    
    func testGroupWillStart(for test: String, in suite: any TestSuite) {
        // Increase tests counter
        if knownTests.isNew(test: test, in: suite.name, and: suite.module.name) {
            _counters.update { $0.newTests += 1 }
        }
    }
    
    func testGroupConfiguration(for test: String, meta: UnskippableMethodCheckerFactory, in suite: any TestSuite) -> TestRetryGroupConfiguration {
        // If we can retry this test - setup test group for retries
        return checkStatus(for: test, in: suite) ? .retry(success: .atLeastOneSucceeded) : .next(update: nil)
    }
    
    func testWillStart(test: any TestRun, retryReason: String?, skipStatus: SkipStatus,
                       executionCount: Int, failedExecutionCount: Int)
    {
        guard retryReason == id else { return }
        test.set(tag: DDEfdTags.testIsRetry, value: "true")
        test.set(tag: DDEfdTags.testRetryReason, value: DDTagValues.retryReasonEfd)
    }
    
    func testGroupRetry(test: any TestRun, duration: TimeInterval, withStatus: TestStatus,
                        skipStatus: SkipStatus, executionCount: Int, failedExecutionCount: Int) -> RetryStatus?
    {
        // EFD should be enabled for this test
        guard checkStatus(for: test) else { return nil }
        
        // Check how much repeats do we have
        let repeats = slowTestRetries.repeats(for: duration)
        if executionCount < Int(repeats) - 1 {
            // We can retry test
            return .retry
        } else {
            if repeats == 0 {
                // Test is too long. EFD failed
                test.set(tag: DDEfdTags.testEfdAbortReason, value: DDTagValues.efdAbortSlow)
            }
            if failedExecutionCount >= executionCount {
                // All previous executions failed
                // Record errors for the current which is the last
                return .recordErrors
            } else {
                // We have at least one succeded. Pass
                return .pass
            }
        }
    }
    
    func shouldSuppressError(test: any TestRun, skipStatus: SkipStatus, executionCount: Int, failedExecutionCount: Int) -> Bool {
        // if EFD enabled for this test suppress the error for now. We will handle it after in willFinish
        return checkStatus(for: test)
    }
    
    func stop() {}
}

struct EarlyFlakeDetectionFactory: FeatureFactory {
    typealias FT = EarlyFlakeDetection
    
    let knownTests: KnownTests
    let settings: TracerSettings.EFD
    
    static func isEnabled(config: Config, env: Environment, remote: TracerSettings) -> Bool {
        remote.efdIsEnabled && config.efdEnabled
    }
    
    init(knownTests: KnownTests,
         settings: TracerSettings.EFD)
    {
        self.knownTests = knownTests
        self.settings = settings
    }
    
    func create(log: Logger) -> EarlyFlakeDetection? {
        log.debug("Early Flake Detection Enabled")
        return EarlyFlakeDetection(knownTests: knownTests,
                                   slowTestRetries: settings.slowTestRetries,
                                   faultySessionThreshold: settings.faultySessionThreshold,
                                   log: log)
    }
}

extension EarlyFlakeDetection {
    struct Counters {
        var newTests: UInt = 0
        var knownTests: UInt = 0
    }
}
