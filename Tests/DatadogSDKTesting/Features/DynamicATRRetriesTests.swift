/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting

final class DynamicATRRetriesLogicTests: XCTestCase {
    // MARK: - Duration-based retry budgets from EFD settings

    func testDynamicAtrUsesEfdRetryBudgetsForFastTest() async throws {
        let (runner, _) = runner(tests: ["someTest": .fail("Should fail", duration: 1.0)])

        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        // EFD 5s bucket → 10 retries → 1 initial + 10 retries = 11 runs
        XCTAssertEqual(tests["someTest"]?.runs.count, 11)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 11)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
    }

    func testDynamicAtrUsesEfdRetryBudgetsForMediumTest() async throws {
        let (runner, _) = runner(tests: ["someTest": .fail("Should fail", duration: 31.0)])

        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        // EFD 30-60s bucket → 5 retries → 1 initial + 5 retries = 6 runs
        XCTAssertEqual(tests["someTest"]?.runs.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 6)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
    }

    func testDynamicAtrUsesEfdRetryBudgetsForVeryLongTest() async throws {
        let (runner, _) = runner(tests: ["someTest": .fail("Should fail", duration: 700.0)])

        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        // EFD >5m bucket → 0 retries, but max(1, 0) = 1 → 1 initial + 1 retry = 2 runs
        XCTAssertEqual(tests["someTest"]?.runs.count, 2)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 2)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
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
        // >300s bucket → index 4 → 1 retry → 1 initial + 1 retry = 2 runs
        XCTAssertEqual(tests["someTest"]?.runs.count, 2)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 2)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
    }

    func testDynamicAtrCustomBucketsUseFixedExactAndFractionalBoundaries() async throws {
        let buckets: (UInt, UInt, UInt, UInt, UInt) = (1, 2, 3, 4, 5)
        let cases: [(duration: TimeInterval, retries: Int)] = [
            (5, 1), (5.1, 2),
            (10, 2), (10.1, 3),
            (30, 3), (30.1, 4),
            (300, 4), (300.1, 5)
        ]

        for (duration, retries) in cases {
            let (runner, _) = runner(tests: ["someTest": .fail("Should fail", duration: duration)],
                                     customBuckets: buckets)
            let tests = try await extractTests(runner.run())
            XCTAssertEqual(tests["someTest"]?.runs.count, retries + 1,
                           "duration \(duration) should use \(retries) retries")
        }
    }

    func testDynamicAtrInitialDurationCacheUsesFullTestIdentity() {
        let atr = DynamicATRRetries(failedTestRetriesCount: 5,
                                    failedTestTotalRetriesMax: 1000,
                                    slowTestRetries: .init(),
                                    retriesBuckets: (1, 1, 1, 1, 4))
        let fast = mockTest(module: "FirstModule", suite: "SharedSuite", name: "sharedTest")
        let slow = mockTest(module: "SecondModule", suite: "SharedSuite", name: "sharedTest")
        let firstAttempt = TestRunInfoStart(tags: Mocks.AttachedTags(),
                                            skip: (nil, .init(canBeSkipped: false, markedUnskippable: false)),
                                            retry: nil,
                                            executions: (0, 0))

        withExtendedLifetime((fast.session, slow.session)) {
            _ = atr.testGroupRetry(test: fast.test, duration: 1, withStatus: .fail,
                                    retryStatus: .init(), andInfo: firstAttempt)
            _ = atr.testGroupRetry(test: slow.test, duration: 301, withStatus: .fail,
                                    retryStatus: .init(), andInfo: firstAttempt)

            var fastRetry = firstAttempt
            fastRetry.executions = (1, 1)
            XCTAssertFalse(atr.shouldSuppressError(test: fast.test, info: fastRetry))
        }
    }

    // MARK: - Ignores flat DD_CIVISIBILITY_FLAKY_RETRY_COUNT

    func testDynamicAtrIgnoresFlatRetryCount() async throws {
        // flat limit of 1, but 5s bucket gives 10 → should use 10, not 1
        let (runner, _) = runner(tests: ["someTest": .fail("Should fail", duration: 1.0)],
                                 failedTestRetriesCount: 1)

        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        // 5s bucket → 10 retries (not flat 1) → 11 runs
        XCTAssertEqual(tests["someTest"]?.runs.count, 11)
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

    // MARK: - Session-level retry cap still applies

    func testDynamicAtrRespectsSessionLevelRetryCap() async throws {
        let (runner, _) = runner(tests: ["someTest": .fail("Should fail", duration: 1.0),
                                        "someTest2": .fail("Should fail", duration: 1.0)],
                                 failedTestRetriesCount: 5,
                                 failedTestTotalRetriesMax: 8)

        let tests = try await extractTests(runner.run())
        // someTest: 5s bucket → 10 retries, but capped at 8 total → 1 initial + 8 retries = 9 runs
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 9)
        // someTest2: global cap reached after 8 retries → no retries → 1 run
        XCTAssertNotNil(tests["someTest2"])
        XCTAssertEqual(tests["someTest2"]?.runs.count, 1)
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

    // MARK: - Helpers

    private func mockTest(module: String, suite: String, name: String) -> (session: Mocks.Session, test: Mocks.Test) {
        let session = Mocks.Session(name: "MockTestSession", testTags: [:])
        let testModule = session.module(named: module) as! Mocks.Module
        let testSuite = testModule.startSuite(named: suite, at: nil,
                                              framework: .init(name: "MockRunner", version: "1.0.0")) as! Mocks.Suite
        let group = testSuite.startGroup(named: name)
        let test = group.withTest(named: name) { $0 }
        return (session, test)
    }

    func extractTests(_ session: Mocks.Session) throws -> [String: Mocks.Group] {
        guard let suite = session["ATRModule"]?["ATRSuite"] else {
            throw InternalError(description: "Can't get ATRModule and ATRSuite")
        }
        return suite.tests
    }

    func runner(tests: KeyValuePairs<String, Mocks.Runner.TestMethod>,
                failedTestRetriesCount: UInt = 5,
                failedTestTotalRetriesMax: UInt = 1000,
                customBuckets: (UInt, UInt, UInt, UInt, UInt)? = nil) -> (Mocks.Runner, DynamicATRRetries)
    {
        let atr = DynamicATRRetries(
            failedTestRetriesCount: failedTestRetriesCount,
            failedTestTotalRetriesMax: failedTestTotalRetriesMax,
            slowTestRetries: .init(attrs: ["5s": 10, "30s": 5, "1m": 2, "5m": 1]),
            retriesBuckets: customBuckets
        )
        return (Mocks.Runner(features: [atr, AdditionalTags()],
                              tests: ["ATRModule": ["ATRSuite": .init(tests: tests)]]), atr)
    }
}
