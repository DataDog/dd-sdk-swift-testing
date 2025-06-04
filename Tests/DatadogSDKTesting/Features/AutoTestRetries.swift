/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting

final class AutoTestRetriesLogicTests: XCTestCase {
    func testAtrRetriesFailedTest() throws {
        let runner = runner(known: [], tests: ["someTest": .fail(first: 4)])
        
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.count, 5)
        XCTAssertEqual(tests["someTest"]?.filter { $0.status == .fail }.count, 4)
        XCTAssertEqual(tests["someTest"]?.filter { $0.xcStatus == .pass }.count, 5)
    }
    
    func testAtrDoesntRetryPassedTest() throws {
        let runner = runner(known: [], tests: ["someTest": .pass()])
        
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.count, 1)
        XCTAssertEqual(tests["someTest"]?.filter { $0.status == .pass }.count, 1)
        XCTAssertEqual(tests["someTest"]?.filter { $0.xcStatus == .pass }.count, 1)
    }
    
    func extractTests(_ session: Mocks.Session) throws -> [String: [Mocks.Test]] {
        guard let suite = session["ATRModule"]?["ATRSuite"] else {
            throw InternalError(description: "Can't get ATRModule and ATRSuite")
        }
        return suite.tests.mapValues { $0.runs }
    }
    
    func runner(known: [String], tests: [String: Mocks.Runner.TestMethod]) -> Mocks.Runner {
        let atr = AutomaticTestRetries(failedTestRetriesCount: 5, failedTestRetriesTotalCount: 1000)
        return Mocks.Runner(features: [atr], tests: ["ATRModule": ["ATRSuite": tests]])
    }
}
