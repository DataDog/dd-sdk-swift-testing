/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting
@testable import EventsExporter

final class DynamicATRRetriesLogicTests: XCTestCase {
    // MARK: - Duration-based retry budgets from the backend retry timetable

    func testDynamicAtrUsesTimeTableBudgetForFastTest() async throws {
        let (runner, _) = runner(tests: ["someTest": .fail("Should fail", duration: 1.0)])

        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        // 5s bucket → 10 retries → 1 initial + 10 retries = 11 runs
        XCTAssertEqual(tests["someTest"]?.runs.count, 11)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 11)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
    }

    func testDynamicAtrUsesTimeTableBudgetForMediumTest() async throws {
        let (runner, _) = runner(tests: ["someTest": .fail("Should fail", duration: 31.0)])

        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        // 31s is under the "1m" threshold → 2 retries → 1 initial + 2 retries = 3 runs
        XCTAssertEqual(tests["someTest"]?.runs.count, 3)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 3)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
    }

    func testDynamicAtrDoesNotRetryTestLongerThanTheTimeTable() async throws {
        let (runner, _) = runner(tests: ["someTest": .fail("Should fail", duration: 700.0)])

        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        // Longer than the last bucket of the timetable → no retries
        XCTAssertEqual(tests["someTest"]?.runs.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 1)
        // The error of the only run must not stay suppressed
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
    }

    func testDynamicAtrFallsBackToFlatCountWithoutTimeTable() async throws {
        let (runner, _) = runner(tests: ["someTest": .fail("Should fail", duration: 1.0)],
                                 slowTestRetries: .init(),
                                 failedTestRetriesCount: 2)

        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        // An empty timetable gives no budget for any duration, so the flat count is used instead
        XCTAssertEqual(tests["someTest"]?.runs.count, 3)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
    }

    // MARK: - Duration-based retry budgets from custom env buckets

    func testDynamicAtrUsesCustomBucketsForFastTest() async throws {
        let (runner, _) = runner(tests: ["someTest": .fail("Should fail", duration: 1.0)],
                                 customBuckets: (3, 1, 1, 1, 1))

        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        // 5s bucket → 3 retries → 1 initial + 3 retries = 4 runs
        XCTAssertEqual(tests["someTest"]?.runs.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 4)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
    }

    func testDynamicAtrUsesCustomBucketsForLongTest() async throws {
        let (runner, _) = runner(tests: ["someTest": .fail("Should fail", duration: 700.0)],
                                 customBuckets: (5, 4, 3, 2, 1))

        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        // >5m bucket → 1 retry → 1 initial + 1 retry = 2 runs
        XCTAssertEqual(tests["someTest"]?.runs.count, 2)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 2)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
    }

    func testDynamicAtrCustomBucketsUseStrictUpperBounds() async throws {
        let buckets: AutomaticTestRetries.RetryBuckets = (1, 2, 3, 4, 5)
        // Thresholds are strict: a duration equal to one belongs to the next bucket
        let cases: [(duration: TimeInterval, retries: Int)] = [
            (4.9, 1), (5, 2),
            (9.9, 2), (10, 3),
            (29.9, 3), (30, 4),
            (299.9, 4), (300, 5)
        ]

        for (duration, retries) in cases {
            let (runner, _) = runner(tests: ["someTest": .fail("Should fail", duration: duration)],
                                     customBuckets: buckets)
            let tests = try await extractTests(runner.run())
            XCTAssertEqual(tests["someTest"]?.runs.count, retries + 1,
                           "duration \(duration) should use \(retries) retries")
        }
    }

    // MARK: - Stops after first pass

    func testDynamicAtrStopsAfterFirstPass() async throws {
        let (runner, _) = runner(tests: ["someTest": .fail(first: 2, 1.0)],
                                 customBuckets: (5, 1, 1, 1, 1))

        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        // 5s bucket → 5 max retries, but test passes on 3rd run (2 failures + 1 pass)
        XCTAssertEqual(tests["someTest"]?.runs.count, 3)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 2)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .pass }.count, 1)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
    }

    // MARK: - Passing test not retried

    func testDynamicAtrDoesNotRetryPassingTest() async throws {
        let (runner, _) = runner(tests: ["someTest": .pass(1.0)])

        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .pass }.count, 1)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
    }

    // MARK: - Non retriable test

    func testDynamicAtrDoesNotRetryNonRetriableTest() async throws {
        let (runner, atr) = runner(tests: ["someTest": .fail("Should fail", tags: .init(retriable: false))],
                                   customBuckets: (3, 1, 1, 1, 1))

        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(atr.failedTestTotalRetries, 0)
    }

    // MARK: - Session-level retry cap still applies

    func testDynamicAtrRespectsSessionLevelRetryCap() async throws {
        let (runner, atr) = runner(tests: ["someTest": .fail("Should fail", duration: 1.0),
                                           "someTest2": .fail("Should fail", duration: 1.0)],
                                   failedTestTotalRetriesMax: 8)

        let tests = try await extractTests(runner.run())
        // someTest: 5s bucket → 10 retries, but capped at 8 total → 1 initial + 8 retries = 9 runs
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 9)
        // someTest2: global cap reached → no retries → 1 run
        XCTAssertNotNil(tests["someTest2"])
        XCTAssertEqual(tests["someTest2"]?.runs.count, 1)
        XCTAssertEqual(atr.failedTestTotalRetries, 8)
    }

    // MARK: - Retry reason tags

    func testDynamicAtrSetsRetryReasonTags() async throws {
        let (runner, _) = runner(tests: ["someTest": .fail(first: 2, 1.0)],
                                 customBuckets: (3, 1, 1, 1, 1))

        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 3)
        // First run is not a retry
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        // Retries have ATR tags
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 2)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 2)
    }

    // MARK: - Budget

    func testRetryBudgetForDuration() {
        let table = TracerSettings.EFD.TimeTable(attrs: ["5s": 10, "30s": 5, "1m": 2, "5m": 1])
        let timeTable = AutomaticTestRetries.RetryBudget.timeTable(table)
        for duration in [0.0, 1.0, 5.0, 30.0, 61.0, 300.0, 700.0] {
            XCTAssertEqual(timeTable.retries(for: duration), table.repeats(for: duration),
                           "timetable budget must follow the backend timetable at \(duration)")
        }
        XCTAssertEqual(timeTable.maxRetries, 10)

        let buckets = AutomaticTestRetries.RetryBudget.buckets((5, 4, 3, 2, 1))
        XCTAssertEqual(buckets.retries(for: 4.9), 5)
        XCTAssertEqual(buckets.retries(for: 5), 4)
        XCTAssertEqual(buckets.retries(for: 299.9), 2)
        XCTAssertEqual(buckets.retries(for: 300), 1)
        XCTAssertEqual(buckets.maxRetries, 5)

        let flat = AutomaticTestRetries.RetryBudget.flat(3)
        XCTAssertEqual(flat.retries(for: 1), 3)
        XCTAssertEqual(flat.retries(for: 700), 3)
        XCTAssertEqual(flat.maxRetries, 3)

        XCTAssertFalse(flat.isDynamic)
        XCTAssertTrue(buckets.isDynamic)
        XCTAssertTrue(timeTable.isDynamic)
    }

    // MARK: - Enablement

    func testDynamicAtrRequiresAutomaticTestRetries() {
        let env = Environment(config: Config(), env: ProcessEnvironmentReader(environment: [:], infoDictionary: [:]),
                              log: Log.instance)
        func isEnabled(atr: Bool, dynamic: Bool, remote: Bool) -> Bool {
            AutomaticTestRetriesFactory.isEnabled(config: config(dynamic: dynamic, atrEnabled: atr),
                                                  env: env, remote: settings(flakyTestRetriesEnabled: remote))
        }
        // The dynamic budget doesn't enable the feature on its own: ATR has to be enabled
        // both locally and by the backend
        XCTAssertFalse(isEnabled(atr: false, dynamic: true, remote: true))
        XCTAssertFalse(isEnabled(atr: true, dynamic: true, remote: false))
        XCTAssertTrue(isEnabled(atr: true, dynamic: true, remote: true))
        // ATR can be enabled while the dynamic budget is not
        XCTAssertTrue(isEnabled(atr: true, dynamic: false, remote: true))
    }

    // MARK: - Factory

    func testFactoryBudgetSelection() async throws {
        let table = TracerSettings.EFD.TimeTable(attrs: ["5s": 10])
        let log = Mocks.CatchLogger(isDebug: false)

        let flat = try await AutomaticTestRetriesFactory(config: config(dynamic: false),
                                                         efdSettings: .init(slowTestRetries: table))
            .create(log: log)
        XCTAssertFalse(flat.budget.isDynamic)
        XCTAssertEqual(flat.budget.retries(for: 1), 5)

        let dynamic = try await AutomaticTestRetriesFactory(config: config(dynamic: true),
                                                            efdSettings: .init(slowTestRetries: table))
            .create(log: log)
        XCTAssertTrue(dynamic.budget.isDynamic)
        XCTAssertEqual(dynamic.budget.retries(for: 1), 10)

        // Dynamic ATR without a backend timetable falls back to the flat retry count
        let noTable = try await AutomaticTestRetriesFactory(config: config(dynamic: true))
            .create(log: log)
        XCTAssertFalse(noTable.budget.isDynamic)
        XCTAssertEqual(noTable.budget.retries(for: 1), 5)

        // Custom buckets win over the backend timetable
        let custom = try await AutomaticTestRetriesFactory(config: config(dynamic: true, buckets: "3,2,2,1,1"),
                                                           efdSettings: .init(slowTestRetries: table))
            .create(log: log)
        XCTAssertTrue(custom.budget.isDynamic)
        XCTAssertEqual(custom.budget.retries(for: 1), 3)
        XCTAssertEqual(custom.budget.retries(for: 700), 1)
    }

    // MARK: - Helpers

    private func config(dynamic: Bool, buckets: String? = nil, atrEnabled: Bool = true) -> Config {
        var env: [String: String] = ["DD_CIVISIBILITY_DYNAMIC_ATR_ENABLED": dynamic ? "true" : "false",
                                     "DD_CIVISIBILITY_FLAKY_RETRY_ENABLED": atrEnabled ? "true" : "false"]
        if let buckets {
            env["DD_CIVISIBILITY_DYNAMIC_ATR_BUCKETS"] = buckets
        }
        return Config(env: ProcessEnvironmentReader(environment: env, infoDictionary: [:]))
    }

    private func settings(flakyTestRetriesEnabled: Bool) -> TracerSettings {
        TracerSettings(itr: .init(), efd: .init(),
                       flakyTestRetriesEnabled: flakyTestRetriesEnabled,
                       knownTestsEnabled: false, testManagement: .init())
    }

    func extractTests(_ session: Mocks.Session) throws -> [String: Mocks.Group] {
        guard let suite = session["ATRModule"]?["ATRSuite"] else {
            throw InternalError(description: "Can't get ATRModule and ATRSuite")
        }
        return suite.tests
    }

    func runner(tests: KeyValuePairs<String, Mocks.Runner.TestMethod>,
                slowTestRetries: TracerSettings.EFD.TimeTable = .init(attrs: ["5s": 10, "30s": 5, "1m": 2, "5m": 1]),
                failedTestRetriesCount: UInt = 5,
                failedTestTotalRetriesMax: UInt = 1000,
                customBuckets: AutomaticTestRetries.RetryBuckets? = nil) -> (Mocks.Runner, AutomaticTestRetries)
    {
        let atr = AutomaticTestRetries(budget: budget(slowTestRetries: slowTestRetries,
                                                      failedTestRetriesCount: failedTestRetriesCount,
                                                      customBuckets: customBuckets),
                                       failedTestTotalRetriesMax: failedTestTotalRetriesMax)
        return (Mocks.Runner(features: [atr, AdditionalTags()],
                             tests: ["ATRModule": ["ATRSuite": .init(tests: tests)]]), atr)
    }

    private func budget(slowTestRetries: TracerSettings.EFD.TimeTable,
                        failedTestRetriesCount: UInt,
                        customBuckets: AutomaticTestRetries.RetryBuckets?) -> AutomaticTestRetries.RetryBudget
    {
        if let customBuckets {
            return .buckets(customBuckets)
        }
        // The same fallback the factory does for an empty backend timetable
        return slowTestRetries.times.isEmpty ? .flat(failedTestRetriesCount) : .timeTable(slowTestRetries)
    }
}
