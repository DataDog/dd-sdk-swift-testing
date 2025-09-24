/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

final class AutomaticTestRetries: TestHooksFeature {
    static var id: FeatureId = "Automatic Test Retries"
    
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
    
    func testGroupConfiguration(for test: String, meta: UnskippableMethodCheckerFactory,
                                in suite: any TestSuite,
                                configuration: RetryGroupConfiguration.Iterator) -> RetryGroupConfiguration.Iterator
    {
        // Retry but allow softer successStrategy
        configuration.retry(softer: .atLeastOneSucceeded)
    }
    
    func testGroupRetry(test: any TestRun, duration: TimeInterval,
                        withStatus status: TestStatus, retryStatus: RetryStatus.Iterator,
                        andInfo info: TestRunInfoStart) -> RetryStatus.Iterator
    {
        if case .fail = status {
            if info.executions.total < failedTestRetriesCount // we can retry more
               && incrementRetries() != nil // and increased global retry counter successfully
            {
                // we can retry this test more
                return retryStatus.retry(reason: DDTagValues.retryReasonAutoTestRetry,
                                         ignoreErrors: true)
            } else {
                // we can't retry anymore, end it
                return retryStatus.end()
            }
        }
        return retryStatus.next()
    }
    
    func shouldSuppressError(test: any TestRun, info: TestRunInfoStart) -> Bool {
        return info.executions.total < failedTestRetriesCount // we can retry test more
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
