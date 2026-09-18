/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@preconcurrency internal import EventsExporter

final class AutomaticTestRetries: TestHooksFeature {
    static var id: FeatureId = "Automatic Test Retries"

    /// Retry budgets for the Dynamic ATR duration buckets.
    /// Values are the retry counts for the `< 5s`, `< 10s`, `< 30s`, `< 5m` and `>= 5m` buckets.
    /// Thresholds are strict upper bounds, the same way the backend retry timetable works.
    typealias RetryBuckets = (UInt, UInt, UInt, UInt, UInt)

    /// How many times one test can be retried.
    enum RetryBudget {
        /// The same retry count for every test.
        case flat(UInt)
        /// Dynamic ATR: retry count for the duration buckets configured by the user.
        case buckets(RetryBuckets)
        /// Dynamic ATR: retry count from the retry timetable provided by the backend.
        /// The timetable is the same one Early Flake Detection uses, so buckets and
        /// their boundaries are defined by the backend.
        case timeTable(TracerSettings.EFD.TimeTable)

        /// Retries allowed for a test which run for `duration`.
        func retries(for duration: TimeInterval) -> UInt {
            switch self {
            case .flat(let count):
                return count
            case .buckets(let buckets):
                switch duration {
                case ..<5: return buckets.0
                case ..<10: return buckets.1
                case ..<30: return buckets.2
                case ..<300: return buckets.3
                default: return buckets.4
                }
            case .timeTable(let table):
                return table.repeats(for: duration)
            }
        }

        /// The biggest retry count this budget can return. We don't know the duration
        /// of the run while it is still running, so error suppression uses this upper bound.
        var maxRetries: UInt {
            switch self {
            case .flat(let count):
                return count
            case .buckets(let buckets):
                return max(buckets.0, buckets.1, buckets.2, buckets.3, buckets.4)
            case .timeTable(let table):
                return table.times.map { $0.count }.max() ?? 0
            }
        }

        var isDynamic: Bool {
            switch self {
            case .flat: return false
            default: return true
            }
        }
    }

    let budget: RetryBudget
    let failedTestTotalRetriesMax: UInt

    private let _failedTestTotalRetries: Synced<UInt>
    var failedTestTotalRetries: UInt { _failedTestTotalRetries.value }

    init(budget: RetryBudget,
         failedTestTotalRetriesMax: UInt)
    {
        self.budget = budget
        self.failedTestTotalRetriesMax = failedTestTotalRetriesMax
        self._failedTestTotalRetries = Synced(0)
    }

    /// Creates ATR with the same retry count for every test.
    convenience init(failedTestRetriesCount: UInt,
                     failedTestTotalRetriesMax: UInt)
    {
        self.init(budget: .flat(failedTestRetriesCount),
                  failedTestTotalRetriesMax: failedTestTotalRetriesMax)
    }

    func testGroupConfiguration(for test: String, tags: any TestTags,
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
        guard info.tags.get(tag: .retriable) ?? true else { return retryStatus.next() }
        if case .fail = status {
            // Retry budget of the dynamic ATR depends on how long the run took
            if info.executions.total < budget.retries(for: duration) // we can retry more
               && incrementRetries() != nil // and increased global retry counter successfully
            {
                // we can retry this test more
                return retryStatus.retry(reason: DDTagValues.retryReasonAutoTestRetry,
                                         errors: .suppressed(reason: DDTagValues.failureSuppressionReasonATR))
            } else {
                // we can't retry anymore, end it
                return retryStatus.end()
            }
        }
        return retryStatus.next()
    }

    func shouldSuppressError(test: any TestRun, info: TestRunInfoStart) -> Bool {
        guard info.tags.get(tag: .retriable) ?? true else { return false }
        // The run isn't finished yet, so its duration is unknown and we can't tell the exact
        // budget of the dynamic ATR. We suppress the error while any retry is still possible.
        // `testGroupRetry` restores it if the duration leaves us no retries.
        return info.executions.total < budget.maxRetries // we can retry test more
            && _failedTestTotalRetries.value < failedTestTotalRetriesMax // and global counter allow us to retry
    }

    func testWillFinish(test: any TestRun, duration: TimeInterval, withStatus status: TestStatus, andInfo info: TestRunInfoEnd) {
        guard info.retry.feature == id else { return }
        if !info.retry.status.isRetry { // last run. Save status
            // We have to fix status for the suppressed errors if needed.
            test.set(tag: DDTestTags.testFinalStatus,
                     value: status.final(ignoreErrors: info.retry.status.ignoreErrors))
        }
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
    let efdSettings: TracerSettings.EFD
    let telemetry: Telemetry?

    init(config: Config, efdSettings: TracerSettings.EFD = .init(), telemetry: Telemetry? = nil) {
        self.config = config
        self.efdSettings = efdSettings
        self.telemetry = telemetry
    }

    static func isEnabled(config: Config, env: Environment, remote: TracerSettings) -> Bool {
        remote.flakyTestRetriesEnabled && config.testRetriesEnabled
    }

    func create(log: Logger) async throws -> AutomaticTestRetries {
        let budget = budget(log: log)
        report(budget: budget)
        return AutomaticTestRetries(budget: budget,
                                    failedTestTotalRetriesMax: config.testRetriesTotalRetryCount)
    }

    /// Reports the budget we ended up with, so a dynamic ATR which fell back to the
    /// flat retry count isn't counted as enabled.
    private func report(budget: AutomaticTestRetries.RetryBudget) {
        guard let telemetry else { return }
        switch budget {
        case .flat: break
        case .buckets: telemetry.metrics.dynamicATR.enabled.add(hasCustomBuckets: true)
        case .timeTable: telemetry.metrics.dynamicATR.enabled.add(hasCustomBuckets: false)
        }
    }

    private func budget(log: Logger) -> AutomaticTestRetries.RetryBudget {
        let flat = AutomaticTestRetries.RetryBudget.flat(config.testRetriesTestRetryCount)
        guard config.dynamicATREnabled else {
            log.debug("Dynamic Auto Test Retries Disabled. Static retry count: \(flat.maxRetries)")
            return flat
        }
        if let buckets = config.dynamicATRBuckets {
            log.debug("Dynamic Auto Test Retries Enabled with custom buckets: \(buckets)")
            return .buckets(buckets)
        }
        guard !efdSettings.slowTestRetries.times.isEmpty else {
            log.print("Dynamic Auto Test Retries: the backend didn't provide a retry timetable. Falling back to the flat retry count")
            return flat
        }
        log.debug("Dynamic Auto Test Retries Enabled with the backend retry timetable: \(efdSettings.slowTestRetries)")
        return .timeTable(efdSettings.slowTestRetries)
    }
}
