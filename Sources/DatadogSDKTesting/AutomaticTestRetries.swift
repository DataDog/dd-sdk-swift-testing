/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

class AutomaticTestRetries: TestHooksFeature, @unchecked Sendable {
    static var id: FeatureId = "Automatic Test Retries"

    let failedTestRetriesCount: UInt
    let failedTestTotalRetriesMax: UInt

    private let retryTimings: RetryTimings
    private let minimumRetryCount: UInt
    private let usesInitialDuration: Bool

    /// Stable identity for a test across XCTest and Swift Testing execution paths.
    private struct TestIdentity: Hashable {
        let module: String
        let suite: String
        let name: String

        init(_ test: any TestRun) {
            module = test.module.name
            suite = test.suite.name
            name = test.name
        }
    }

    /// Retry budgets for regular ATR, backend EFD fallback, or custom Dynamic ATR buckets.
    private enum RetryTimings {
        case constant(UInt)
        case efd(TracerSettings.EFD.TimeTable)
        case dynamic((UInt, UInt, UInt, UInt, UInt))

        func retries(for duration: TimeInterval) -> UInt {
            switch self {
            case let .constant count:
                return count
            case let .efd table:
                return table.retries(forDuration: duration)
            case let .dynamic buckets:
                switch duration {
                case ...5: return buckets.0
                case ...10: return buckets.1
                case ...30: return buckets.2
                case ...300: return buckets.3
                default: return buckets.4
                }
            }
        }
    }

    /// Dynamic ATR classifies the initial attempt once. Flat ATR does not need this cache.
    private let initialDurationCache: Synced<[TestIdentity: TimeInterval]> = .init([:])
    private let _failedTestTotalRetries: Synced<UInt>
    var failedTestTotalRetries: UInt { _failedTestTotalRetries.value }

    /// Creates regular ATR with one retry count for every test duration.
    init(failedTestRetriesCount: UInt,
         failedTestTotalRetriesMax: UInt)
    {
        self.failedTestRetriesCount = failedTestRetriesCount
        self.failedTestTotalRetriesMax = failedTestTotalRetriesMax
        self.retryTimings = .constant(failedTestRetriesCount)
        self.minimumRetryCount = 0
        self.usesInitialDuration = false
        self._failedTestTotalRetries = Synced(0)
    }

    /// Creates Dynamic ATR. Custom buckets use fixed inclusive product boundaries;
    /// otherwise the backend EFD timetable supplies duration-specific budgets.
    init(failedTestRetriesCount: UInt,
         failedTestTotalRetriesMax: UInt,
         slowTestRetries: TracerSettings.EFD.TimeTable,
         retriesBuckets: (UInt, UInt, UInt, UInt, UInt)? = nil)
    {
        self.failedTestRetriesCount = failedTestRetriesCount
        self.failedTestTotalRetriesMax = failedTestTotalRetriesMax
        self.retryTimings = retriesBuckets.map(RetryTimings.dynamic) ?? .efd(slowTestRetries)
        self.minimumRetryCount = 1
        self.usesInitialDuration = true
        self._failedTestTotalRetries = Synced(0)
    }

    private func maxRetries(for test: any TestRun) -> UInt {
        guard usesInitialDuration else { return failedTestRetriesCount }
        guard let initialDuration = initialDurationCache.value[TestIdentity(test)] else {
            // Ensure the first failing attempt is suppressed while its duration is recorded.
            return minimumRetryCount
        }
        return max(minimumRetryCount, retryTimings.retries(for: initialDuration))
    }

    func testGroupConfiguration(for test: String, tags: any TestTags,
                                in suite: any TestSuite,
                                configuration: RetryGroupConfiguration.Iterator) -> RetryGroupConfiguration.Iterator
    {
        configuration.retry(softer: .atLeastOneSucceeded)
    }

    func testGroupRetry(test: any TestRun, duration: TimeInterval,
                        withStatus status: TestStatus, retryStatus: RetryStatus.Iterator,
                        andInfo info: TestRunInfoStart) -> RetryStatus.Iterator
    {
        guard info.tags.get(tag: .retriable) ?? true else { return retryStatus.next() }

        if usesInitialDuration && info.executions.total == 0 {
            let identity = TestIdentity(test)
            initialDurationCache.update {
                if $0[identity] == nil {
                    $0[identity] = duration
                }
            }
        }

        if case .fail = status {
            if UInt(info.executions.total) < maxRetries(for: test)
               && incrementRetries() != nil
            {
                return retryStatus.retry(reason: DDTagValues.retryReasonAutoTestRetry,
                                         errors: .suppressed(reason: DDTagValues.failureSuppressionReasonATR))
            } else {
                return retryStatus.end()
            }
        }
        return retryStatus.next()
    }

    func shouldSuppressError(test: any TestRun, info: TestRunInfoStart) -> Bool {
        guard info.tags.get(tag: .retriable) ?? true else { return false }
        return UInt(info.executions.total) < maxRetries(for: test)
            && failedTestTotalRetries < failedTestTotalRetriesMax
    }

    func testWillFinish(test: any TestRun, duration: TimeInterval, withStatus status: TestStatus, andInfo info: TestRunInfoEnd) {
        guard info.retry.feature == id else { return }
        if !info.retry.status.isRetry {
            test.set(tag: DDTestTags.testFinalStatus,
                     value: status.final(ignoreErrors: info.retry.status.ignoreErrors))
        }
    }

    func incrementRetries() -> UInt? {
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
    let efdSettings: TracerSettings.EFD

    init(config: Config, efdSettings: TracerSettings.EFD = .init()) {
        self.config = config
        self.efdSettings = efdSettings
    }

    static func isEnabled(config: Config, env: Environment, remote: TracerSettings) -> Bool {
        remote.flakyTestRetriesEnabled && config.testRetriesEnabled
    }

    func create(log: Logger) async throws -> AutomaticTestRetries {
        if config.dynamicATREnabled {
            log.debug("Dynamic Auto Test Retries Enabled")
            return AutomaticTestRetries(
                failedTestRetriesCount: config.testRetriesTestRetryCount,
                failedTestTotalRetriesMax: config.testRetriesTotalRetryCount,
                slowTestRetries: efdSettings.slowTestRetries,
                retriesBuckets: config.dynamicATRBuckets
            )
        }

        log.debug("Automatic Test Retries Enabled")
        return AutomaticTestRetries(failedTestRetriesCount: config.testRetriesTestRetryCount,
                                    failedTestTotalRetriesMax: config.testRetriesTotalRetryCount)
    }
}
