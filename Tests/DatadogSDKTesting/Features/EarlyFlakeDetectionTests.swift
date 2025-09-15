/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
@testable import EventsExporter
import OpenTelemetryApi
import OpenTelemetrySdk
import CodeCoverage
import XCTest

final class EarlyFlakeDetectionLogicTests: XCTestCase {
    func testEfdRetriesNewTest() throws {
        let (runner, efd) = efdRunner(known: [],
                                      tests: ["newTest": .failOddRuns(1.0)])
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["newTest"])
        XCTAssertEqual(tests["newTest"]?.runs.count, 10)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.status == .fail }.count, 5)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.xcStatus == .pass }.count, 10)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == "true" }.count, 10)
        XCTAssertEqual(tests["newTest"]?.isSucceeded, true)
        XCTAssertEqual(efd.testCounters.newTests, 1)
        XCTAssertEqual(efd.testCounters.knownTests, 1)
        
        XCTAssertNil(tests["newTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["newTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 9)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonEarlyFlakeDetection }.count, 9)
        XCTAssertNil(tests["newTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries])
    }
    
    func testEfdRetriesNewSuccessTest() throws {
        let (runner, efd) = efdRunner(known: [],
                                      tests: ["newTest": .pass(1.0)])
        
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["newTest"])
        XCTAssertEqual(tests["newTest"]?.runs.count, 10)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.status == .pass }.count, 10)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.xcStatus == .pass }.count, 10)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == "true" }.count, 10)
        XCTAssertEqual(tests["newTest"]?.isSucceeded, true)
        XCTAssertEqual(efd.testCounters.newTests, 1)
        XCTAssertEqual(efd.testCounters.knownTests, 1)
        
        XCTAssertNil(tests["newTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["newTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 9)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonEarlyFlakeDetection }.count, 9)
        XCTAssertNil(tests["newTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries])
    }
    
    func testEfdRetriesNewFailureTest() throws {
        let (runner, efd) = efdRunner(known: [],
                                      tests: ["newTest": .fail("should fail", duration: 1.0)])
        
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["newTest"])
        XCTAssertEqual(tests["newTest"]?.runs.count, 10)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.status == .fail }.count, 10)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == "true" }.count, 10)
        XCTAssertEqual(tests["newTest"]?.isSucceeded, false)
        XCTAssertEqual(efd.testCounters.newTests, 1)
        XCTAssertEqual(efd.testCounters.knownTests, 1)
        
        XCTAssertNil(tests["newTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["newTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 9)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonEarlyFlakeDetection }.count, 9)
        XCTAssertEqual(tests["newTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries], "true")
    }
    
    func testEfdDoesntRetryOldTest() throws {
        let (runner, efd) = efdRunner(known: ["oldTest"],
                                      tests: ["oldTest": .fail("Should fail")])
        
        let tests = try extractTests(runner.run())
        
        XCTAssertNotNil(tests["oldTest"])
        XCTAssertEqual(tests["oldTest"]?.runs.count, 1)
        XCTAssertEqual(tests["oldTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["oldTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["oldTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == nil }.count, 1)
        XCTAssertEqual(tests["oldTest"]?.isSucceeded, false)
        XCTAssertEqual(efd.testCounters.newTests, 0)
        XCTAssertEqual(efd.testCounters.knownTests, 1)
        
        XCTAssertNil(tests["oldTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["oldTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
    }
    
    // EFD + ATR
    func testAtrWorksWithEFDForOldTest() throws {
        let (runner, efd) = efdAndAtrRunner(known: ["oldTest"],
                                            tests: ["oldTest": .fail(first: 3, 1.0)])
        
        let tests = try extractTests(runner.run())
        
        XCTAssertNotNil(tests["oldTest"])
        XCTAssertEqual(tests["oldTest"]?.runs.count, 4)
        XCTAssertEqual(tests["oldTest"]?.runs.filter { $0.status == .fail }.count, 3)
        XCTAssertEqual(tests["oldTest"]?.runs.filter { $0.xcStatus == .pass }.count, 4)
        XCTAssertEqual(tests["oldTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == nil }.count, 4)
        XCTAssertEqual(tests["oldTest"]?.isSucceeded, true)
        XCTAssertEqual(efd.testCounters.newTests, 0)
        XCTAssertEqual(efd.testCounters.knownTests, 1)
        
        XCTAssertNil(tests["oldTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["oldTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertEqual(tests["oldTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 3)
        XCTAssertEqual(tests["oldTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 3)
    }
    
    func testEFDDisablesATRForNewTest() throws {
        let (runner, efd) = efdAndAtrRunner(known: ["oldTest"],
                                            tests: ["newTest": .fail(first: 5, 1.0),
                                                    "oldTest": .fail(first: 3, 1.0)])
        
        let tests = try extractTests(runner.run())
        
        XCTAssertNotNil(tests["oldTest"])
        XCTAssertEqual(tests["oldTest"]?.runs.count, 4)
        XCTAssertEqual(tests["oldTest"]?.runs.filter { $0.status == .fail }.count, 3)
        XCTAssertEqual(tests["oldTest"]?.runs.filter { $0.xcStatus == .pass }.count, 4)
        XCTAssertEqual(tests["oldTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == nil }.count, 4)
        XCTAssertEqual(tests["oldTest"]?.isSucceeded, true)
        
        XCTAssertNil(tests["oldTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["oldTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertEqual(tests["oldTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 3)
        XCTAssertEqual(tests["oldTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 3)
        
        XCTAssertNotNil(tests["newTest"])
        XCTAssertEqual(tests["newTest"]?.runs.count, 10)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.status == .fail }.count, 5)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.xcStatus == .pass }.count, 10)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == "true" }.count, 10)
        XCTAssertEqual(tests["newTest"]?.isSucceeded, true)
        
        XCTAssertEqual(efd.testCounters.newTests, 1)
        XCTAssertEqual(efd.testCounters.knownTests, 2)
        
        XCTAssertNil(tests["newTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["newTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 9)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonEarlyFlakeDetection }.count, 9)
    }
    
    func testEfdChangesRetryCountForLongTest() throws {
        let (runner, efd) = efdRunner(known: [],
                                      tests: ["newTest": .failOddRuns(61.0)])
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["newTest"])
        XCTAssertEqual(tests["newTest"]?.runs.count, 2)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.xcStatus == .pass }.count, 2)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == "true" }.count, 2)
        XCTAssertEqual(efd.testCounters.newTests, 1)
        XCTAssertEqual(efd.testCounters.knownTests, 1)
        XCTAssertEqual(tests["newTest"]?.isSucceeded, true)
        
        XCTAssertNil(tests["newTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["newTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 1)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonEarlyFlakeDetection }.count, 1)
    }
    
    func testEfdChangesRetryCountForLongLongTest() throws {
        let (runner, efd) = efdRunner(known: [],
                                      tests: ["newTest": .failOddRuns(700.0)])
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["newTest"])
        XCTAssertEqual(tests["newTest"]?.runs.count, 1)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.xcStatus == .pass }.count, 0)
        XCTAssertEqual(tests["newTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == "true" }.count, 1)
        XCTAssertEqual(tests["newTest"]?.isSucceeded, false)
        XCTAssertEqual(efd.testCounters.newTests, 1)
        XCTAssertEqual(efd.testCounters.knownTests, 1)
        
        XCTAssertNil(tests["newTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["newTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
    }
    
    func extractTests(_ session: Mocks.Session) throws -> [String: Mocks.Group] {
        guard let suite = session["EFDModule"]?["EFDSuite"] else {
            throw InternalError(description: "Can't get EFDModule and EFDSuite")
        }
        return suite.tests
    }
    
    func efdRunner(known: [String], tests: KeyValuePairs<String, Mocks.Runner.TestMethod>) -> (Mocks.Runner, EarlyFlakeDetection) {
        let efd = EarlyFlakeDetection(
            knownTests: KnownTests(tests: ["EFDModule": ["EFDSuite": known]]),
            slowTestRetries: .init(attrs: ["5s": 10, "30s": 5, "1m": 2, "5m": 1]),
            faultySessionThreshold: 30,
            log: Mocks.CatchLogger(isDebug: false)
        )
        let knownFeature = KnownTests(tests: ["EFDModule": ["EFDSuite": known]])
        return (Mocks.Runner(features: [efd, knownFeature], tests: ["EFDModule": ["EFDSuite": tests]]), efd)
    }
    
    func efdAndAtrRunner(known: [String], tests: KeyValuePairs<String, Mocks.Runner.TestMethod>) -> (Mocks.Runner, EarlyFlakeDetection) {
        let runner = efdRunner(known: known, tests: tests)
        let atr = AutomaticTestRetries(failedTestRetriesCount: 5, failedTestTotalRetriesMax: 1000)
        runner.0.features.insert(atr, at: 1)
        return runner
    }
}
