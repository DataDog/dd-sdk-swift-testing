/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting
@testable import EventsExporter

class TestManagementTests: XCTestCase {
    func testTMSkipsDisabledTest() throws {
        let runner = tmRunner(disabled: ["disabledTest"],
                              tests: ["someTest": .fail("Always fails"),
                                      "disabledTest": .fail("Always fails")])
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["disabledTest"])
        XCTAssertEqual(tests["disabledTest"]?.runs.count, 1)
        XCTAssertEqual(tests["disabledTest"]?.runs.filter { $0.status == .skip }.count, 1)
        XCTAssertEqual(tests["disabledTest"]?.runs.filter { $0.xcStatus == .skip }.count, 1)
        XCTAssertEqual(tests["disabledTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == nil
        }.count, 1)
        XCTAssertEqual(tests["disabledTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["disabledTest"]?.isSkipped, true)
        XCTAssertEqual(tests["disabledTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["disabledTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusSkip)
        
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == nil
        }.count, 1)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }
    
    func testTMRunsQuarantinedTestAndSuppressesResult() throws {
        let runner = tmRunner(quarantined: ["quarantinedTest"],
                              tests: ["someTest": .fail("Always fails"),
                                      "quarantinedTest": .fail("Always fails")])
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["quarantinedTest"])
        XCTAssertEqual(tests["quarantinedTest"]?.runs.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.xcStatus == .pass }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == DDTagValues.failureSuppressionReasonQuarantine
        }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["quarantinedTest"]?.isSkipped, false)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
        
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == nil
        }.count, 1)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }
    
    func testTMRunsQuarantinedTestAndSuppressesResultAndATRWorks() throws {
        let runner = tmAndAtrRunner(quarantined: ["quarantinedTest"],
                                    tests: ["someTest": .fail("Always fails"),
                                            "quarantinedTest": .fail(first: 4)])
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["quarantinedTest"])
        XCTAssertEqual(tests["quarantinedTest"]?.runs.count, 5)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.status == .fail }.count, 4)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.status == .pass }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.xcStatus == .pass }.count, 5)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 4)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 4)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == DDTagValues.failureSuppressionReasonATR
        }.count, 4)
        XCTAssertNil(tests["quarantinedTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries])
        XCTAssertEqual(tests["quarantinedTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["quarantinedTest"]?.isSkipped, false)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
        
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .pass }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries], "true")
        XCTAssertEqual(tests["someTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == DDTagValues.failureSuppressionReasonATR
        }.count, 5)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }
    
    func testTMRunsQuarantinedTestAndSuppressesResultWhenATRFails() throws {
        let runner = tmAndAtrRunner(quarantined: ["quarantinedTest"],
                                    tests: ["someTest": .fail("Always fails"),
                                            "quarantinedTest": .fail("Always fails")])
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["quarantinedTest"])
        XCTAssertEqual(tests["quarantinedTest"]?.runs.count, 6)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.status == .fail }.count, 6)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.xcStatus == .pass }.count, 6)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 5)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 5)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries], "true")
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == DDTagValues.failureSuppressionReasonATR
        }.count, 5)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == DDTagValues.failureSuppressionReasonQuarantine
        }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["quarantinedTest"]?.isSkipped, false)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
        
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .pass }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries], "true")
        XCTAssertEqual(tests["someTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == DDTagValues.failureSuppressionReasonATR
        }.count, 5)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }
    
    func testTMAttemptToFixWorks() throws {
        let runner = tmAndAtrRunner(fix: ["atfTest"],
                                    tests: ["someTest": .fail("Always fails"),
                                            "atfTest": .pass()])
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["atfTest"])
        XCTAssertEqual(tests["atfTest"]?.runs.count, 20)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.status == .pass }.count, 20)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.xcStatus == .pass }.count, 20)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 19)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAttemptToFix }.count, 19)
        XCTAssertNil(tests["atfTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries])
        XCTAssertEqual(tests["atfTest"]?.runs.last?.tags[DDTestManagementTags.testAttemptToFixPassed], "true")
        XCTAssertEqual(tests["atfTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == nil
        }.count, 20)
        XCTAssertEqual(tests["atfTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["atfTest"]?.isSkipped, false)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["atfTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
        
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .pass }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries], "true")
        XCTAssertEqual(tests["someTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == DDTagValues.failureSuppressionReasonATR
        }.count, 5)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }
    
    func testTMAttemptToFixFailsForFailedTest() throws {
        let runner = tmAndAtrRunner(fix: ["atfTest"],
                                    tests: ["someTest": .fail("Always fails"),
                                            "atfTest": .fail(first: 3)])
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["atfTest"])
        XCTAssertEqual(tests["atfTest"]?.runs.count, 20)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.status == .pass }.count, 17)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.status == .fail }.count, 3)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.xcStatus == .pass }.count, 17)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.xcStatus == .fail }.count, 3)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 19)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAttemptToFix }.count, 19)
        XCTAssertNil(tests["atfTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries])
        XCTAssertEqual(tests["atfTest"]?.runs.last?.tags[DDTestManagementTags.testAttemptToFixPassed], "false")
        XCTAssertEqual(tests["atfTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == nil
        }.count, 20)
        XCTAssertEqual(tests["atfTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["atfTest"]?.isSkipped, false)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["atfTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
        
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .pass }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries], "true")
        XCTAssertEqual(tests["someTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == DDTagValues.failureSuppressionReasonATR
        }.count, 5)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }
    
    func testTMAttemptToFixDoesntFailForDisabledTest() throws {
        let runner = tmAndAtrRunner(fix: ["atfTest"], disabled: ["atfTest"],
                                    tests: ["someTest": .fail("Always fails"),
                                            "atfTest": .fail(first: 3)])
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["atfTest"])
        XCTAssertEqual(tests["atfTest"]?.runs.count, 20)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.status == .pass }.count, 17)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.status == .fail }.count, 3)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.xcStatus == .pass }.count, 20)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.xcStatus == .fail }.count, 0)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 19)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAttemptToFix }.count, 19)
        XCTAssertNil(tests["atfTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries])
        XCTAssertEqual(tests["atfTest"]?.runs.last?.tags[DDTestManagementTags.testAttemptToFixPassed], "false")
        XCTAssertEqual(tests["atfTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == DDTagValues.failureSuppressionReasonDisabled
        }.count, 3)
        XCTAssertEqual(tests["atfTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["atfTest"]?.isSkipped, false)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["atfTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
        
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .pass }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries], "true")
        XCTAssertEqual(tests["someTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == DDTagValues.failureSuppressionReasonATR
        }.count, 5)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }
    
    func testTMAttemptToFixDoesntFailForQuarantinedTest() throws {
        let runner = tmAndAtrRunner(fix: ["atfTest"], quarantined: ["atfTest"],
                                    tests: ["someTest": .fail("Always fails"),
                                            "atfTest": .fail(first: 3)])
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["atfTest"])
        XCTAssertEqual(tests["atfTest"]?.runs.count, 20)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.status == .pass }.count, 17)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.status == .fail }.count, 3)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.xcStatus == .pass }.count, 20)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.xcStatus == .fail }.count, 0)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 19)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAttemptToFix }.count, 19)
        XCTAssertNil(tests["atfTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries])
        XCTAssertEqual(tests["atfTest"]?.runs.last?.tags[DDTestManagementTags.testAttemptToFixPassed], "false")
        XCTAssertEqual(tests["atfTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["atfTest"]?.isSkipped, false)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["atfTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
        
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .pass }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries], "true")
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }
    
    func tmRunner(fix: [String] = [], disabled: [String] = [],
                  quarantined: [String] = [], tests: KeyValuePairs<String, Mocks.Runner.TestMethod>) -> Mocks.Runner
    {
        var tmTests = [String: TestManagementTestsInfo.Test]()
        for test in fix {
            tmTests[test] = .init(attemptToFix: true)
        }
        for test in disabled {
            if let existing = tmTests[test] {
                tmTests[test] = existing.and(disabled: true)
            } else {
                tmTests[test] = .init(disabled: true)
            }
        }
        for test in quarantined {
            if let existing = tmTests[test] {
                tmTests[test] = existing.and(quarantined: true)
            } else {
                tmTests[test] = .init(quarantined: true)
            }
        }
        let tmSuite = TestManagementTestsInfo.Suite(tests: tmTests)
        let tmModule = TestManagementTestsInfo.Module(suites: ["TMSuite": tmSuite])
        let tmInfo = TestManagementTestsInfo(modules: ["TMModule": tmModule])
        let tm = TestManagement(tests: tmInfo, attemptToFixRetries: 20, module: "TMModule")
        return Mocks.Runner(features: [tm, RetryAndSkipTags()], tests: ["TMModule": ["TMSuite": tests]])
    }
    
    func tmAndAtrRunner(fix: [String] = [], disabled: [String] = [],
                        quarantined: [String] = [],
                        tests: KeyValuePairs<String, Mocks.Runner.TestMethod>) -> Mocks.Runner
    {
        let runner = tmRunner(fix: fix, disabled: disabled, quarantined: quarantined, tests: tests)
        let atr = AutomaticTestRetries(failedTestRetriesCount: 5, failedTestTotalRetriesMax: 1000)
        runner.features.insert(atr, at: runner.features.count - 1)
        return runner
    }
    
    func extractTests(_ session: Mocks.Session) throws -> [String: Mocks.Group] {
        guard let suite = session["TMModule"]?["TMSuite"] else {
            throw InternalError(description: "Can't get TMModule and TMSuite")
        }
        return suite.tests
    }
}

extension TestManagementTestsInfo.Test {
    func and(disabled: Bool) -> Self {
        .init(disabled: disabled, quarantined: self.properties.quarantined, attemptToFix: self.properties.attemptToFix)
    }
    
    func and(quarantined: Bool) -> Self {
        .init(disabled: self.properties.disabled, quarantined: quarantined, attemptToFix: self.properties.attemptToFix)
    }
}
