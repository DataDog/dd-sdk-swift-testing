/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@preconcurrency internal import EventsExporter

final class EarlyFlakeDetection: TestHooksFeature {
    static var id: FeatureId = "Early Flake Detection"
    
    struct State {
        var newTests: UInt = 0
        var knownTests: UInt = 0
        var sessionFailed: Bool = false
    }
    
    let knownTests: KnownTests
    let knownTestsCount: Double
    let slowTestRetries: TracerSettings.EFD.TimeTable
    let faultySessionThreshold: Double
    
    let log: Logger
    private let _state: Synced<State>
    
    // used in tests
    var testCounters: (newTests: UInt, knownTests: UInt) {
        let state = _state.value
        return (state.newTests, state.knownTests)
    }
    
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
        self._state = Synced(.init())
        self.log = log
    }
    
    private func checkStatus(for test: any TestRun) -> Bool {
        checkStatus(for: test.name, in: test.suite)
    }
    
    private func checkStatus(for test: String, in suite: any TestSuite) -> Bool {
        // Calculate threshold
        let isNotFailed = _state.update { state in
            guard !state.sessionFailed else { return false }
            let testsCount = max(self.knownTestsCount, Double(state.knownTests))
            let newTests = Double(state.newTests)
            guard newTests <= self.faultySessionThreshold || ((newTests / testsCount) * 100.0) < self.faultySessionThreshold else {
                self.log.print("Early Flake Detection Faulty Session detected!")
                state.sessionFailed = true
                return false
            }
            return true
        }
        return isNotFailed && knownTests.isNew(test: test, in: suite.name, and: suite.module.name)
    }
    
    func testSessionWillEnd(session: any TestSession) {
        session.set(tag: DDEfdTags.testEfdEnabled, value: "true")
        if _state.value.sessionFailed {
            session.set(tag: DDEfdTags.testEfdAbortReason, value: DDTagValues.efdAbortFaulty)
        }
    }

    func testModuleWillEnd(module: any TestModule) {
        module.set(tag: DDEfdTags.testEfdEnabled, value: "true")
        if _state.value.sessionFailed {
            module.set(tag: DDEfdTags.testEfdAbortReason, value: DDTagValues.efdAbortFaulty)
        }
    }

    func testSuiteWillStart(suite: any TestSuite, testsCount: UInt) {
        _state.update { $0.knownTests += testsCount }
    }
    
    func testGroupWillStart(for test: String, in suite: any TestSuite) {
        // Increase tests counter
        if knownTests.isNew(test: test, in: suite.name, and: suite.module.name) {
            _state.update { $0.newTests += 1 }
        }
    }
    
    func testGroupConfiguration(for test: String, tags: any TestTags,
                                in suite: any TestSuite,
                                configuration: RetryGroupConfiguration.Iterator) -> RetryGroupConfiguration.Iterator
    {
        // If we can retry this test - setup test group for retries.
        // Allow softer retry strategy
        return checkStatus(for: test, in: suite)
            ? configuration.retry(softer: .atLeastOneSucceeded)
            : configuration.next()
    }
    
    func testGroupRetry(test: any TestRun, duration: TimeInterval,
                        withStatus status: TestStatus, retryStatus: RetryStatus.Iterator,
                        andInfo info: TestRunInfoStart) -> RetryStatus.Iterator
    {
        guard info.tags.get(tag: .retriable) ?? true else { return retryStatus.next() }
        // EFD should be enabled for this test
        guard checkStatus(for: test) else { return retryStatus.next() }

        // Early exit: once we've seen both a failure and a success, the test is flaky
        switch status {
        case .fail:
            if info.executions.total > info.executions.failed {
                return retryStatus.end(errors: .suppressed(reason: DDTagValues.failureSuppressionReasonEFD))
            }
        case .pass:
            if info.executions.failed > 0 {
                return retryStatus.end(errors: .suppressed(reason: DDTagValues.failureSuppressionReasonEFD))
            }
        default: break
        }

        // Check how much repeats do we have
        let repeats = slowTestRetries.repeats(for: duration)
        if info.executions.total < Int(repeats) - 1 {
            // We can retry test
            return retryStatus.retry(reason: DDTagValues.retryReasonEarlyFlakeDetection,
                                     errors: .suppressed(reason: DDTagValues.failureSuppressionReasonEFD))
        } else {
            if repeats == 0 {
                // Test is too long. EFD failed
                test.set(tag: DDEfdTags.testEfdAbortReason, value: DDTagValues.efdAbortSlow)
            }
            if info.executions.failed >= info.executions.total {
                // All previous executions failed
                // Record errors for the current which is the last
                return retryStatus.end()
            } else {
                // We have at least one succeded. Pass
                return retryStatus.end(errors: .suppressed(reason: DDTagValues.failureSuppressionReasonEFD))
            }
        }
    }
    
    func shouldSuppressError(test: any TestRun, info: TestRunInfoStart) -> Bool {
        guard info.tags.get(tag: .retriable) ?? true else { return false }
        // if EFD enabled for this test suppress the error for now. We will handle it after in testGroupRetry
        return checkStatus(for: test)
    }
    
    func testWillFinish(test: any TestRun, duration: TimeInterval, withStatus status: TestStatus, andInfo info: TestRunInfoEnd) {
        guard info.retry.feature == id else { return }
        // Set final status for test
        if !info.retry.status.isRetry {
            // We have to fix status for the suppressed errors if needed.
            test.set(tag: DDTestTags.testFinalStatus,
                     value: status.final(ignoreErrors: info.retry.status.ignoreErrors))
        }
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
