/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

final class AutomaticTestRetries: TestHooksFeature {
    static var id: String = "Automatic Test Retries"
    
    let failedTestRetriesCount: UInt
    let failedTestTotalRetriesMax: UInt
    
    private var _failedTestTotalRetries: Synced<UInt>
    var failedTestTotalRetries: UInt { _failedTestTotalRetries.value }
    
    init(failedTestRetriesCount: UInt,
         failedTestTotalRetriesMax: UInt)
    {
        self.failedTestRetriesCount = failedTestRetriesCount
        self.failedTestTotalRetriesMax = failedTestTotalRetriesMax
        self._failedTestTotalRetries = Synced(0)
    }
    
    func testWillStart(test: any TestRun, retryReason: String?, skipStatus: SkipStatus,
                       executionCount: Int, failedExecutionCount: Int)
    {
        guard retryReason == id else { return }
        test.set(tag: DDEfdTags.testIsRetry, value: "true")
        test.set(tag: DDEfdTags.testRetryReason, value: DDTagValues.retryReasonAtr)
    }
    
    func testGroupConfiguration(for test: String, meta: UnskippableMethodCheckerFactory, in suite: any TestSuite) -> TestRetryGroupConfiguration {
        return .retry(success: .atLeastOneSucceeded)
    }
    
    func testGroupRetry(test: any TestRun, duration: TimeInterval, withStatus status: TestStatus,
                        skipStatus: SkipStatus, executionCount: Int, failedExecutionCount: Int) -> RetryStatus?
    {
        if case .fail = status {
            if executionCount < failedTestRetriesCount // we can retry more
               && incrementRetries() != nil // and increased global retry counter successfully
            {
                // we can retry this test more
                return .retry
            } else {
                // we can't retry anymore, record errors if we have them
                return .recordErrors
            }
        }
        return nil
    }
    
    
    func shouldSuppressError(test: any TestRun, skipStatus: SkipStatus, executionCount: Int, failedExecutionCount: Int) -> Bool {
        return executionCount < failedTestRetriesCount // we can retry test more
            && _failedTestTotalRetries.value < failedTestTotalRetriesMax // and global counter allow us to retry
    }
    
    private func incrementRetries() -> UInt? {
        _failedTestTotalRetries.update { cnt in
            cnt.checkedAdd(1, max: failedTestTotalRetriesMax).map {
                cnt = $0
                return $0
            }
        }
    }
    
    func stop() {}
}

struct AutomaticTestRetriesFactory: FeatureFactory {
    typealias FT = AutomaticTestRetries
    
    let config: Config
    
    init(config: Config) {
        self.config = config
    }
    
    static func isEnabled(config: Config, env: Environment, remote: TracerSettings) -> Bool {
        remote.flakyTestRetriesEnabled && config.testRetriesEnabled
    }
    
    func create(log: Logger) -> AutomaticTestRetries? {
        log.debug("Automatic Test Retries Enabled")
        return AutomaticTestRetries(failedTestRetriesCount: config.testRetriesTestRetryCount,
                                    failedTestTotalRetriesMax: config.testRetriesTotalRetryCount)
    }
}
