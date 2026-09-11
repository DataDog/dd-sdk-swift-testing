/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

/// Duration-based Auto Test Retries: classifies each test once by its initial-attempt
/// duration into EFD buckets and uses a per-bucket retry budget instead of the flat
/// per-test retry limit. The session-level retry cap still applies.
final class DynamicATRRetries: AutomaticTestRetries, @unchecked Sendable {
    let slowTestRetries: TracerSettings.EFD.TimeTable
    let retriesBuckets: (UInt, UInt, UInt, UInt, UInt)?

    /// Caches the initial-attempt duration per test name so the classification
    /// is computed once and reused across all retries of that test.
    private let _initialDurationCache: Synced<[String: TimeInterval]> = .init([:])

    init(failedTestRetriesCount: UInt,
         failedTestTotalRetriesMax: UInt,
         slowTestRetries: TracerSettings.EFD.TimeTable,
         retriesBuckets: (UInt, UInt, UInt, UInt, UInt)? = nil)
    {
        self.slowTestRetries = slowTestRetries
        self.retriesBuckets = retriesBuckets
        super.init(failedTestRetriesCount: failedTestRetriesCount,
                   failedTestTotalRetriesMax: failedTestTotalRetriesMax)
    }

    /// Returns the duration-based max retries for a test, using the cached initial
    /// duration. Falls back to 1 (minimum retry budget) if the initial duration is
    /// not yet cached, ensuring error suppression on the initial run.
    private func maxRetries(for testName: String) -> UInt {
        guard let initialDuration = _initialDurationCache.value[testName] else {
            return 1
        }
        let bucketIndex = slowTestRetries.retryBucketIndex(forDuration: initialDuration)
        if let buckets = retriesBuckets {
            let allBuckets = [buckets.0, buckets.1, buckets.2, buckets.3, buckets.4]
            let idx = min(bucketIndex, allBuckets.count - 1)
            return max(1, allBuckets[idx])
        } else {
            return max(1, slowTestRetries.retries(forDuration: initialDuration))
        }
    }

    override func testGroupRetry(test: any TestRun, duration: TimeInterval,
                                withStatus status: TestStatus, retryStatus: RetryStatus.Iterator,
                                andInfo info: TestRunInfoStart) -> RetryStatus.Iterator
    {
        guard info.tags.get(tag: .retriable) ?? true else { return retryStatus.next() }

        // Cache the initial-attempt duration on the first run (executions.total == 0).
        if info.executions.total == 0 {
            _initialDurationCache.update { $0[test.name] = duration }
        }

        if case .fail = status {
            let maxRetries = self.maxRetries(for: test.name)
            if UInt(info.executions.total) < maxRetries // we can retry more
               && incrementRetries() != nil // and increased global retry counter successfully
            {
                return retryStatus.retry(reason: DDTagValues.retryReasonAutoTestRetry,
                                         errors: .suppressed(reason: DDTagValues.failureSuppressionReasonATR))
            } else {
                return retryStatus.end()
            }
        }
        return retryStatus.next()
    }

    override func shouldSuppressError(test: any TestRun, info: TestRunInfoStart) -> Bool {
        guard info.tags.get(tag: .retriable) ?? true else { return false }
        let maxRetries = self.maxRetries(for: test.name)
        return UInt(info.executions.total) < maxRetries // we can retry test more
            && failedTestTotalRetries < failedTestTotalRetriesMax // and global counter allow us to retry
    }
}

struct DynamicATRRetriesFactory: FeatureFactory {
    typealias FT = DynamicATRRetries

    let config: Config
    let efdSettings: TracerSettings.EFD

    init(config: Config, efdSettings: TracerSettings.EFD) {
        self.config = config
        self.efdSettings = efdSettings
    }

    static func isEnabled(config: Config, env: Environment, remote: TracerSettings) -> Bool {
        remote.flakyTestRetriesEnabled && config.testRetriesEnabled && config.dynamicATREnabled
    }

    func create(log: Logger) async throws -> DynamicATRRetries {
        log.debug("Dynamic Auto Test Retries Enabled")
        return DynamicATRRetries(
            failedTestRetriesCount: config.testRetriesTestRetryCount,
            failedTestTotalRetriesMax: config.testRetriesTotalRetryCount,
            slowTestRetries: efdSettings.slowTestRetries,
            retriesBuckets: config.dynamicATRBuckets
        )
    }
}
