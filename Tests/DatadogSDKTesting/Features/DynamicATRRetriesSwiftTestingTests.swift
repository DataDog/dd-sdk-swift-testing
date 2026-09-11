/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting

final class DynamicATRRetriesSwiftTestingTests: XCTestCase {
    func testDynamicAtrRetriesFailedTestWithCustomBuckets() async throws {
        let (runner, _) = runner(tests: ["someTest": .fail("Should fail", duration: 1.0)],
                                customBuckets: (3, 1, 1, 1, 1))

        let tests = try await extractTests(try await runner.run())
        XCTAssertNotNil(tests["someTest"])
        // 5s bucket → 3 retries → 1 initial + 3 retries = 4 runs
        XCTAssertEqual(tests["someTest"]?.runs.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 4)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
    }

    func testDynamicAtrUsesEfdBucketsWhenNoCustomBuckets() async throws {
        let (runner, _) = runner(tests: ["someTest": .fail("Should fail", duration: 1.0)])

        let tests = try await extractTests(try await runner.run())
        XCTAssertNotNil(tests["someTest"])
        // EFD 5s bucket → 10 retries → 11 runs
        XCTAssertEqual(tests["someTest"]?.runs.count, 11)
    }

    func testDynamicAtrCustomBucketsUseFixedFractionalBoundary() async throws {
        let (runner, _) = runner(tests: ["someTest": .fail("Should fail", duration: 5.1)],
                                 customBuckets: (1, 2, 3, 4, 5))

        let tests = try await extractTests(try await runner.run())
        // 5.1s is in the >5s and <=10s bucket, so it gets two retries.
        XCTAssertEqual(tests["someTest"]?.runs.count, 3)
    }

    func testDynamicAtrStopsAfterFirstPass() async throws {
        let (runner, _) = runner(tests: ["someTest": .fail(first: 2, 1.0)],
                                customBuckets: (5, 1, 1, 1, 1))

        let tests = try await extractTests(try await runner.run())
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 3)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
    }

    func testDynamicAtrIgnoresFlatRetryCount() async throws {
        let (runner, _) = runner(tests: ["someTest": .fail("Should fail", duration: 1.0)],
                                failedTestRetriesCount: 1)

        let tests = try await extractTests(try await runner.run())
        XCTAssertNotNil(tests["someTest"])
        // 5s bucket → 10 retries (not flat 1) → 11 runs
        XCTAssertEqual(tests["someTest"]?.runs.count, 11)
    }

    func testDynamicAtrDoesNotRetryPassingTest() async throws {
        let (runner, _) = runner(tests: ["someTest": .pass(1.0)])

        let tests = try await extractTests(try await runner.run())
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 1)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
    }

    func testDynamicAtrSetsRetryReasonTags() async throws {
        let (runner, _) = runner(tests: ["someTest": .fail(first: 2, 1.0)],
                                customBuckets: (3, 1, 1, 1, 1))

        let tests = try await extractTests(try await runner.run())
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 3)
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 2)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 2)
    }

    // MARK: - Helpers

    func extractTests(_ session: Mocks.Session) throws -> [String: Mocks.Group] {
        guard let suite = session["ATRModule"]?["ATRSuite"] else {
            throw InternalError(description: "Can't get ATRModule and ATRSuite")
        }
        return suite.tests
    }

    func runner(tests: KeyValuePairs<String, Mocks.Runner.TestMethod>,
                failedTestRetriesCount: UInt = 5,
                failedTestTotalRetriesMax: UInt = 1000,
                customBuckets: (UInt, UInt, UInt, UInt, UInt)? = nil) -> (Mocks.STRunner, DynamicATRRetries)
    {
        let atr = DynamicATRRetries(
            failedTestRetriesCount: failedTestRetriesCount,
            failedTestTotalRetriesMax: failedTestTotalRetriesMax,
            slowTestRetries: .init(attrs: ["5s": 10, "30s": 5, "1m": 2, "5m": 1]),
            retriesBuckets: customBuckets
        )
        return (Mocks.STRunner(features: [atr, AdditionalTags()],
                               tests: ["ATRModule": ["ATRSuite": .init(tests: tests)]]), atr)
    }
}
