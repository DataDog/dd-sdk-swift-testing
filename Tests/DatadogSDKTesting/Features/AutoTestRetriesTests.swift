/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting

final class AutoTestRetriesLogicTests: XCTestCase {
    func testAtrRetriesFailedTest() async throws {
        let (runner, atr) = runner(tests: ["someTest": .fail(first: 4)])
        
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .pass }.count, 5)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
        XCTAssertEqual(atr.failedTestTotalRetries, 4)
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
        XCTAssertNil(tests["someTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries])
    }
    
    func testAtrDoesntRetryPassedTest() async throws {
        let (runner, atr) = runner(tests: ["someTest": .pass()])
        
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .pass }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .pass }.count, 1)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
        XCTAssertEqual(atr.failedTestTotalRetries, 0)
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDTestTags.testHasFailedAllRetries])
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
    }
    
    func testAtrRetriesFailedTestAndFailsLastIfAllFailed() async throws {
        let (runner, atr) = runner(tests: ["someTest": .fail("Should fail")])
        
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .pass }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.xcStatus, .fail)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(atr.failedTestTotalRetries, 5)
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries], "true")
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }
    
    func testAtrRetriesFailedTestAndPassesIfLastPassed() async throws {
        let (runner, atr) = runner(tests: ["someTest": .fail(first: 5)])
        
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .pass }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .pass }.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.last?.status, .pass)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
        XCTAssertEqual(atr.failedTestTotalRetries, 5)
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 5)
        XCTAssertNil(tests["someTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries])
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
    }
    
    func testAtrStopRetryingAfterGlobalMaxReached() async throws {
        let (runner, atr) = runner(tests: ["someTest": .fail(first: 5),
                                           "someTest2": .fail("Should fail")],
                                   failedTestRetriesCount: 5,
                                   failedTestTotalRetriesMax: 8)
        
        let tests = try await extractTests(runner.run())
        
        // "someTest" should have all 6 runs (main + 5 retries), last is successful
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .pass }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .pass }.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.last?.status, .pass)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 5)
        XCTAssertNil(tests["someTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries])
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
        
        // someTest2 should have only 4 runs (main + 3 retries) because global limit of 8 reached
        XCTAssertNotNil(tests["someTest2"])
        XCTAssertEqual(tests["someTest2"]?.runs.count, 4)
        XCTAssertEqual(tests["someTest2"]?.runs.filter { $0.status == .fail }.count, 4)
        XCTAssertEqual(tests["someTest2"]?.runs.filter { $0.xcStatus == .pass }.count, 3)
        XCTAssertEqual(tests["someTest2"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["someTest2"]?.runs.last?.xcStatus, .fail)
        XCTAssertEqual(tests["someTest2"]?.isSucceeded, false)
        XCTAssertNil(tests["someTest2"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["someTest2"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertEqual(tests["someTest2"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 3)
        XCTAssertEqual(tests["someTest2"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 3)
        XCTAssertEqual(tests["someTest2"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries], "true")
        XCTAssertEqual(tests["someTest2"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest2"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
        
        XCTAssertEqual(atr.failedTestTotalRetries, 8)
    }
    
    func testAtrDoesNotRetryNonRetriableTest() async throws {
        let (runner, atr) = runner(tests: ["nonRetriableTest": .fail("Should fail", tags: .init(retriable: false))])

        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["nonRetriableTest"])
        XCTAssertEqual(tests["nonRetriableTest"]?.runs.count, 1)
        XCTAssertEqual(tests["nonRetriableTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["nonRetriableTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["nonRetriableTest"]?.isSucceeded, false)
        XCTAssertEqual(atr.failedTestTotalRetries, 0)
        XCTAssertNil(tests["nonRetriableTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["nonRetriableTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertNil(tests["nonRetriableTest"]?.runs.first?.tags[DDTestTags.testFailureSuppressionReason])
        XCTAssertEqual(tests["nonRetriableTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }

    func testAtrStopsRetryingAfterFirstSuccess() async throws {
        let (runner, atr) = runner(tests: ["someTest": .fail(first: 2)])

        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 3)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 2)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .pass }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .pass }.count, 3)
        XCTAssertEqual(tests["someTest"]?.runs.last?.status, .pass)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
        XCTAssertEqual(atr.failedTestTotalRetries, 2)
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 2)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 2)
        XCTAssertNil(tests["someTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries])
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
    }

    func testAtrRetriesFailedTestAndKnownTestsWork() async throws {
        let (runner, atr) = runner(tests: ["someTest": .fail(first: 4)])
        var features = runner.features.features
        features.append(KnownTests(tests: [:]))
        runner.features = features
        
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .pass }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == "true" }.count, 5)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
        XCTAssertEqual(atr.failedTestTotalRetries, 4)
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 4)
        XCTAssertNil(tests["someTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries])
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
    }
    
    func extractTests(_ session: Mocks.Session) throws -> [String: Mocks.Group] {
        guard let suite = session["ATRModule"]?["ATRSuite"] else {
            throw InternalError(description: "Can't get ATRModule and ATRSuite")
        }
        return suite.tests
    }
    
    func runner(tests: KeyValuePairs<String, Mocks.Runner.TestMethod>,
                failedTestRetriesCount: UInt = 5, failedTestTotalRetriesMax: UInt = 1000) -> (Mocks.Runner, AutomaticTestRetries)
    {
        let atr = AutomaticTestRetries(failedTestRetriesCount: failedTestRetriesCount,
                                       failedTestTotalRetriesMax: failedTestTotalRetriesMax)
        return (Mocks.Runner(features: [atr, AdditionalTags()], tests: ["ATRModule": ["ATRSuite": .init(tests: tests)]]), atr)
    }
}
