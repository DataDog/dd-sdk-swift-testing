/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting

final class AutoTestRetriesLogicTests: XCTestCase {
    func testAtrRetriesFailedTest() throws {
        let (runner, atr) = runner(tests: ["someTest": .fail(first: 4)])
        
        let tests = try extractTests(runner.run())
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
        XCTAssertNil(tests["someTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries])
    }
    
    func testAtrDoesntRetryPassedTest() throws {
        let (runner, atr) = runner(tests: ["someTest": .pass()])
        
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .pass }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .pass }.count, 1)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
        XCTAssertEqual(atr.failedTestTotalRetries, 0)
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDTestTags.testHasFailedAllRetries])
    }
    
    func testAtrRetriesFailedTestAndFailsLastIfAllFailed() throws {
        let (runner, atr) = runner(tests: ["someTest": .fail("Should fail")])
        
        let tests = try extractTests(runner.run())
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
    }
    
    func testAtrRetriesFailedTestAndPassesIfLastPassed() throws {
        let (runner, atr) = runner(tests: ["someTest": .fail(first: 5)])
        
        let tests = try extractTests(runner.run())
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
    }
    
    func testAtrStopRetryingAfterGlobalMaxReached() throws {
        let (runner, atr) = runner(tests: ["someTest": .fail(first: 5),
                                           "someTest2": .fail("Should fail")],
                                   failedTestRetriesCount: 5,
                                   failedTestTotalRetriesMax: 8)
        
        let tests = try extractTests(runner.run())
        
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
        
        XCTAssertEqual(atr.failedTestTotalRetries, 8)
    }
    
    func testAtrRetriesFailedTestAndKnownTestsWork() throws {
        let (runner, atr) = runner(tests: ["someTest": .fail(first: 4)])
        runner.features.append(KnownTests(tests: [:]))
        
        let tests = try extractTests(runner.run())
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
        return (Mocks.Runner(features: [atr], tests: ["ATRModule": ["ATRSuite": tests]]), atr)
    }
}
