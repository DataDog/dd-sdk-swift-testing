/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting
@testable import EventsExporter

class TestManagementTests: XCTestCase {
    func testMutableSpanTagsDoNotActivateExclusionPolicy() async throws {
        let runner = tmAndAtrRunner(quarantined: ["ordinary"], tests: [
            "ordinary": .init {
                Mocks.Test.active?.set(tag: DDTestManagementTags.testNoAutoRetry, value: "true")
                Mocks.Test.active?.set(tag: DDTestManagementTags.testPreventFailureSuppression, value: "true")
                return .fail(.init(type: "Still governed by Datadog automation"))
            }
        ])
        let tests = try await extractTests(runner.run())
        let test = try XCTUnwrap(tests["ordinary"])
        XCTAssertEqual(test.runs.count, 6)
        XCTAssertTrue(test.isSucceeded)
        XCTAssertEqual(test.runs.last?.tags[DDTestTags.testFailureSuppressionReason], DDTagValues.failureSuppressionReasonQuarantine)
    }

    func testBothExclusionsOverrideAllAssignedPoliciesButPreserveAssignmentTags() async throws {
        let runner = tmAndAtrRunner(fix: ["critical"], disabled: ["critical"], quarantined: ["critical"],
                                    tests: ["critical": .fail("Blocking failure", tags: .init(
                                        retriable: false, preventFailureSuppression: true))])
        let tests = try await extractTests(runner.run())
        let test = try XCTUnwrap(tests["critical"])
        XCTAssertEqual(test.runs.count, 1)
        XCTAssertFalse(test.isSucceeded)
        XCTAssertFalse(test.isSkipped)
        let run = try XCTUnwrap(test.runs.first)
        XCTAssertEqual(run.xcStatus, .fail)
        XCTAssertEqual(run.tags[DDTestManagementTags.testNoAutoRetry], "true")
        XCTAssertEqual(run.tags[DDTestManagementTags.testPreventFailureSuppression], "true")
        XCTAssertEqual(run.tags[DDTestManagementTags.testIsQuarantined], "true")
        XCTAssertEqual(run.tags[DDTestManagementTags.testIsTestDisabled], "true")
        XCTAssertEqual(run.tags[DDTestManagementTags.testIsAttemptToFix], "true")
        XCTAssertNil(run.tags[DDTestManagementTags.testAttemptToFixPassed])
        XCTAssertNil(run.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(run.tags[DDTestTags.testFailureSuppressionReason])
    }

    func testNonRetriableReevaluatesDisabledPolicyAfterExcludingAttemptToFix() async throws {
        let runner = tmRunner(fix: ["disabled"], disabled: ["disabled"],
                              tests: ["disabled": .fail("Must not execute", tags: .init(retriable: false))])
        let tests = try await extractTests(runner.run())
        let test = try XCTUnwrap(tests["disabled"])
        XCTAssertEqual(test.runs.count, 1)
        XCTAssertTrue(test.isSkipped)
        let run = try XCTUnwrap(test.runs.first)
        XCTAssertEqual(run.status, .skip)
        XCTAssertEqual(run.tags[DDTestManagementTags.testNoAutoRetry], "true")
        XCTAssertEqual(run.tags[DDTestManagementTags.testIsTestDisabled], "true")
        XCTAssertEqual(run.tags[DDTestManagementTags.testIsAttemptToFix], "true")
        XCTAssertNil(run.tags[DDTestManagementTags.testAttemptToFixPassed])
    }

    func testNonRetriableRetainsQuarantineAfterExcludingAttemptToFix() async throws {
        let runner = tmAndAtrRunner(fix: ["quarantined"], quarantined: ["quarantined"],
                                    tests: ["quarantined": .fail("Suppressed failure", tags: .init(retriable: false))])
        let tests = try await extractTests(runner.run())
        let test = try XCTUnwrap(tests["quarantined"])
        XCTAssertEqual(test.runs.count, 1)
        XCTAssertTrue(test.isSucceeded)
        let run = try XCTUnwrap(test.runs.first)
        XCTAssertEqual(run.status, .fail)
        XCTAssertEqual(run.xcStatus, .pass)
        XCTAssertEqual(run.tags[DDTestTags.testFailureSuppressionReason], DDTagValues.failureSuppressionReasonQuarantine)
        XCTAssertEqual(run.tags[DDTestManagementTags.testIsAttemptToFix], "true")
        XCTAssertNil(run.tags[DDTestManagementTags.testAttemptToFixPassed])
        XCTAssertNil(run.tags[DDEfdTags.testIsRetry])
    }

    func testFailureProtectionDoesNotDisableRetries() async throws {
        let runner = tmAndAtrRunner(disabled: ["critical"], quarantined: ["critical"],
                                    tests: ["critical": .fail(first: 1, tags: .init(preventFailureSuppression: true))])
        let tests = try await extractTests(runner.run())
        let test = try XCTUnwrap(tests["critical"])
        XCTAssertEqual(test.runs.count, 2)
        XCTAssertTrue(test.isSucceeded)
        for run in test.runs {
            XCTAssertEqual(run.tags[DDTestManagementTags.testPreventFailureSuppression], "true")
            XCTAssertEqual(run.tags[DDTestManagementTags.testIsTestDisabled], "true")
            XCTAssertEqual(run.tags[DDTestManagementTags.testIsQuarantined], "true")
            XCTAssertNil(run.tags[DDTestManagementTags.testNoAutoRetry])
        }
    }

    func testFailureProtectionDoesNotTurnPassingTestIntoFailure() async throws {
        let runner = tmRunner(disabled: ["critical"], quarantined: ["critical"],
                              tests: ["critical": .pass(tags: .init(preventFailureSuppression: true))])
        let tests = try await extractTests(runner.run())
        XCTAssertEqual(tests["critical"]?.runs.count, 1)
        XCTAssertEqual(tests["critical"]?.isSucceeded, true)
        XCTAssertEqual(tests["critical"]?.runs.first?.status, .pass)
    }

    func testExclusionsDoNotOverrideTiaOrExplicitSkips() async throws {
        let runner = tmAndTiaRunner(disabled: ["tia"], quarantined: ["tia"], skip: ["tia"], tests: [
            "tia": .fail("Must not execute", tags: .init(retriable: false, preventFailureSuppression: true)),
            "explicit": .skip("Developer skip", tags: .init(retriable: false, preventFailureSuppression: true))
        ])
        let tests = try await extractTests(runner.run())
        for name in ["tia", "explicit"] {
            let test = try XCTUnwrap(tests[name])
            XCTAssertEqual(test.runs.count, 1)
            XCTAssertTrue(test.isSkipped)
            XCTAssertEqual(test.runs.first?.tags[DDTestManagementTags.testNoAutoRetry], "true")
            XCTAssertEqual(test.runs.first?.tags[DDTestManagementTags.testPreventFailureSuppression], "true")
        }
        XCTAssertEqual(tests["tia"]?.runs.first?.tags[DDTestTags.testSkippedByITR], "true")
    }

    func testExcludedAndOrdinaryDeclarationsHaveIndependentPolicies() async throws {
        let runner = tmAndAtrRunner(disabled: ["excluded", "ordinary"], quarantined: ["excluded", "ordinary"], tests: [
            "excluded": .fail("Blocking", tags: .init(retriable: false, preventFailureSuppression: true)),
            "ordinary": .fail("Disabled"),
            "ordinarySibling": .fail(first: 1)
        ])
        let tests = try await extractTests(runner.run())
        XCTAssertEqual(tests["excluded"]?.isSucceeded, false)
        XCTAssertEqual(tests["ordinary"]?.isSkipped, true)
        XCTAssertEqual(tests["ordinarySibling"]?.runs.count, 2)
        for name in ["ordinary", "ordinarySibling"] {
            for run in try XCTUnwrap(tests[name]).runs {
                XCTAssertNil(run.tags[DDTestManagementTags.testNoAutoRetry])
                XCTAssertNil(run.tags[DDTestManagementTags.testPreventFailureSuppression])
            }
        }
    }

    func testAllowedFailureSuppressionKeepsQuarantineAndDisabling() async throws {
        // `preventFailureSuppression: false` is the test-level override of a protected suite
        let runner = tmRunner(disabled: ["disabled"], quarantined: ["quarantined"], tests: [
            "disabled": .fail("Must not execute", tags: .init(preventFailureSuppression: false)),
            "quarantined": .fail("Suppressed failure", tags: .init(preventFailureSuppression: false))
        ])
        let tests = try await extractTests(runner.run())
        XCTAssertEqual(tests["disabled"]?.isSkipped, true)
        XCTAssertEqual(tests["quarantined"]?.isSucceeded, true)
        XCTAssertEqual(tests["quarantined"]?.runs.first?.tags[DDTestTags.testFailureSuppressionReason],
                       DDTagValues.failureSuppressionReasonQuarantine)
        for name in ["disabled", "quarantined"] {
            XCTAssertNil(tests[name]?.runs.first?.tags[DDTestManagementTags.testPreventFailureSuppression])
        }
    }
    
    func testRetriableTagDoesNotEmitNoAutoRetryTag() async throws {
        let runner = tmAndAtrRunner(fix: ["fix"], tests: ["fix": .pass(tags: .init(retriable: true))])
        let tests = try await extractTests(runner.run())
        let test = try XCTUnwrap(tests["fix"])
        XCTAssertGreaterThan(test.runs.count, 1)
        for run in test.runs {
            XCTAssertNil(run.tags[DDTestManagementTags.testNoAutoRetry])
        }
    }

    func testTMSkipsDisabledTest() async throws {
        let runner = tmRunner(disabled: ["disabledTest"],
                              tests: ["someTest": .fail("Always fails"),
                                      "disabledTest": .fail("Always fails")])
        let tests = try await extractTests(runner.run())
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
    
    func testTMRunsQuarantinedTestAndSuppressesResult() async throws {
        let runner = tmRunner(quarantined: ["quarantinedTest"],
                              tests: ["someTest": .fail("Always fails"),
                                      "quarantinedTest": .fail("Always fails")])
        let tests = try await extractTests(runner.run())
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
    
    func testTMRunsQuarantinedTestAndSuppressesResultAndATRWorks() async throws {
        let runner = tmAndAtrRunner(quarantined: ["quarantinedTest"],
                                    tests: ["someTest": .fail("Always fails"),
                                            "quarantinedTest": .fail(first: 4)])
        let tests = try await extractTests(runner.run())
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
    
    func testTMRunsQuarantinedTestAndSuppressesResultWhenATRFails() async throws {
        let runner = tmAndAtrRunner(quarantined: ["quarantinedTest"],
                                    tests: ["someTest": .fail("Always fails"),
                                            "quarantinedTest": .fail("Always fails")])
        let tests = try await extractTests(runner.run())
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
    
    func testTMAttemptToFixWorks() async throws {
        let runner = tmAndAtrRunner(fix: ["atfTest"],
                                    tests: ["someTest": .fail("Always fails"),
                                            "atfTest": .pass()])
        let tests = try await extractTests(runner.run())
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

    func testTMAttemptToFixPassesForDisabledTestWhenAllAttemptsPass() async throws {
        let runner = tmAndAtrRunner(fix: ["atfTest"], disabled: ["atfTest"],
                                    tests: ["atfTest": .pass()])
        let tests = try await extractTests(runner.run())
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
    }

    func testTMAttemptToFixPassesForQuarantinedTestWhenAllAttemptsPass() async throws {
        let runner = tmAndAtrRunner(fix: ["atfTest"], quarantined: ["atfTest"],
                                    tests: ["atfTest": .pass()])
        let tests = try await extractTests(runner.run())
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
    }
    
    func testTMAttemptToFixFailsForFailedTest() async throws {
        let runner = tmAndAtrRunner(fix: ["atfTest"],
                                    tests: ["someTest": .fail("Always fails"),
                                            "atfTest": .fail(first: 3)])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["atfTest"])
        XCTAssertEqual(tests["atfTest"]?.runs.count, 1)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.status == .pass }.count, 0)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.xcStatus == .pass }.count, 0)
        XCTAssertNil(tests["atfTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["atfTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertNil(tests["atfTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries])
        XCTAssertEqual(tests["atfTest"]?.runs.last?.tags[DDTestManagementTags.testAttemptToFixPassed], "false")
        XCTAssertEqual(tests["atfTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == nil
        }.count, 1)
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
    
    func testTMAttemptToFixFailsForDisabledTest() async throws {
        let runner = tmAndAtrRunner(fix: ["atfTest"], disabled: ["atfTest"],
                                    tests: ["someTest": .fail("Always fails"),
                                            "atfTest": .fail(first: 3)])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["atfTest"])
        XCTAssertEqual(tests["atfTest"]?.runs.count, 1)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.status == .pass }.count, 0)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.xcStatus == .pass }.count, 0)
        XCTAssertNil(tests["atfTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["atfTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertNil(tests["atfTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries])
        XCTAssertEqual(tests["atfTest"]?.runs.last?.tags[DDTestManagementTags.testAttemptToFixPassed], "false")
        XCTAssertEqual(tests["atfTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == nil
        }.count, 1)
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
    
    func testTMAttemptToFixFailsForQuarantinedTest() async throws {
        let runner = tmAndAtrRunner(fix: ["atfTest"], quarantined: ["atfTest"],
                                    tests: ["someTest": .fail("Always fails"),
                                            "atfTest": .fail(first: 3)])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["atfTest"])
        XCTAssertEqual(tests["atfTest"]?.runs.count, 1)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.status == .pass }.count, 0)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.xcStatus == .pass }.count, 0)
        XCTAssertNil(tests["atfTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["atfTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertNil(tests["atfTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries])
        XCTAssertEqual(tests["atfTest"]?.runs.last?.tags[DDTestManagementTags.testAttemptToFixPassed], "false")
        XCTAssertEqual(tests["atfTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == nil
        }.count, 1)
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
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }
    
    func testTMWithATRDoesntRetryDisabledTest() async throws {
        let runner = tmAndAtrRunner(disabled: ["disabledTest"],
                                    tests: ["someTest": .fail("Always fails"),
                                            "disabledTest": .fail("Always fails")])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["disabledTest"])
        XCTAssertEqual(tests["disabledTest"]?.runs.count, 1)
        XCTAssertEqual(tests["disabledTest"]?.runs.filter { $0.status == .skip }.count, 1)
        XCTAssertEqual(tests["disabledTest"]?.runs.filter { $0.xcStatus == .skip }.count, 1)
        XCTAssertNil(tests["disabledTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["disabledTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertEqual(tests["disabledTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == nil
        }.count, 1)
        XCTAssertEqual(tests["disabledTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["disabledTest"]?.isSkipped, true)
        XCTAssertEqual(tests["disabledTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["disabledTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusSkip)

        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 6)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .pass }.count, 5)
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

    func testTMDisabledAndQuarantinedBehavesLikeDisabled() async throws {
        let runner = tmRunner(disabled: ["multiTest"], quarantined: ["multiTest"],
                              tests: ["someTest": .fail("Always fails"),
                                      "multiTest": .fail("Always fails")])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["multiTest"])
        XCTAssertEqual(tests["multiTest"]?.runs.count, 1)
        XCTAssertEqual(tests["multiTest"]?.runs.filter { $0.status == .skip }.count, 1)
        XCTAssertEqual(tests["multiTest"]?.runs.filter { $0.xcStatus == .skip }.count, 1)
        XCTAssertEqual(tests["multiTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == nil
        }.count, 1)
        XCTAssertEqual(tests["multiTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["multiTest"]?.isSkipped, true)
        XCTAssertEqual(tests["multiTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["multiTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusSkip)

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

    func testTMDisabledWithEFDSkipsTest() async throws {
        let runner = tmAndEfdRunner(disabled: ["disabledTest"],
                                    known: ["someTest"],
                                    tests: ["someTest": .fail("Always fails"),
                                            "disabledTest": .fail("Always fails")])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["disabledTest"])
        XCTAssertEqual(tests["disabledTest"]?.runs.count, 1)
        XCTAssertEqual(tests["disabledTest"]?.runs.filter { $0.status == .skip }.count, 1)
        XCTAssertEqual(tests["disabledTest"]?.runs.filter { $0.xcStatus == .skip }.count, 1)
        XCTAssertEqual(tests["disabledTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == nil
        }.count, 1)
        XCTAssertEqual(tests["disabledTest"]?.runs.filter {
            $0.tags[DDTestTags.testIsNew] == "true"
        }.count, 1)
        XCTAssertEqual(tests["disabledTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["disabledTest"]?.isSkipped, true)
        XCTAssertEqual(tests["disabledTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["disabledTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusSkip)

        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDTestTags.testIsNew])
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }

    func testTMQuarantinedWithEFDNewTestSuppressesResult() async throws {
        let runner = tmAndEfdRunner(quarantined: ["quarantinedTest"],
                                    known: ["someTest"],
                                    tests: ["someTest": .fail("Always fails"),
                                            "quarantinedTest": .fail("Always fails")])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["quarantinedTest"])
        XCTAssertEqual(tests["quarantinedTest"]?.runs.count, 10)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.status == .fail }.count, 10)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.xcStatus == .pass }.count, 10)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter {
            $0.tags[DDTestTags.testIsNew] == "true"
        }.count, 10)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 9)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter {
            $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonEarlyFlakeDetection
        }.count, 9)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == DDTagValues.failureSuppressionReasonEFD
        }.count, 9)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == DDTagValues.failureSuppressionReasonQuarantine
        }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries], "true")
        XCTAssertEqual(tests["quarantinedTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["quarantinedTest"]?.isSkipped, false)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)

        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDTestTags.testIsNew])
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }

    func testTMQuarantinedWithEFDOldTestBehavesLikeQuarantined() async throws {
        let runner = tmAndEfdRunner(quarantined: ["quarantinedTest"],
                                    known: ["quarantinedTest", "someTest"],
                                    tests: ["someTest": .fail("Always fails"),
                                            "quarantinedTest": .fail("Always fails")])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["quarantinedTest"])
        XCTAssertEqual(tests["quarantinedTest"]?.runs.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.xcStatus == .pass }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == DDTagValues.failureSuppressionReasonQuarantine
        }.count, 1)
        XCTAssertNil(tests["quarantinedTest"]?.runs.first?.tags[DDTestTags.testIsNew])
        XCTAssertEqual(tests["quarantinedTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["quarantinedTest"]?.isSkipped, false)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)

        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDTestTags.testIsNew])
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }

    func testTMDisabledWithTIASkipsTest() async throws {
        let runner = tmAndTiaRunner(disabled: ["disabledTest"],
                                    skip: ["disabledTest"],
                                    tests: ["someTest": .fail("Always fails"),
                                            "disabledTest": .fail("Always fails")])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["disabledTest"])
        XCTAssertEqual(tests["disabledTest"]?.runs.count, 1)
        XCTAssertEqual(tests["disabledTest"]?.runs.filter { $0.status == .skip }.count, 1)
        XCTAssertEqual(tests["disabledTest"]?.runs.filter { $0.xcStatus == .skip }.count, 1)
        XCTAssertNil(tests["disabledTest"]?.runs.first?.tags[DDTestTags.testSkippedByITR])
        XCTAssertEqual(tests["disabledTest"]?.runs.first?.tags[DDTestTags.testSkipReason],
                       "Flaky test is disabled by Datadog")
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
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDTestTags.testSkippedByITR])
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }

    func testTMQuarantinedWithTIASkips() async throws {
        let runner = tmAndTiaRunner(quarantined: ["quarantinedTest"],
                                    skip: ["quarantinedTest"],
                                    tests: ["someTest": .fail("Always fails"),
                                            "quarantinedTest": .fail("Always fails")])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["quarantinedTest"])
        XCTAssertEqual(tests["quarantinedTest"]?.runs.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.status == .skip }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.xcStatus == .skip }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.first?.tags[DDTestTags.testSkippedByITR], "true")
        XCTAssertEqual(tests["quarantinedTest"]?.runs.first?.tags[DDTestTags.testSkipReason],
                       "Skipped by Test Impact Analysis")
        XCTAssertEqual(tests["quarantinedTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["quarantinedTest"]?.isSkipped, true)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusSkip)

        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDTestTags.testSkippedByITR])
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }

    func testTMQuarantinedWithTIARunsSuppressesResult() async throws {
        let runner = tmAndTiaRunner(quarantined: ["quarantinedTest"],
                                    skip: [],
                                    tests: ["someTest": .fail("Always fails"),
                                            "quarantinedTest": .fail("Always fails")])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["quarantinedTest"])
        XCTAssertEqual(tests["quarantinedTest"]?.runs.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.xcStatus == .pass }.count, 1)
        XCTAssertNil(tests["quarantinedTest"]?.runs.first?.tags[DDTestTags.testSkippedByITR])
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
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDTestTags.testSkippedByITR])
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }

    func testAtfStopsOnFirstFailureAfterPasses() async throws {
        let runner = tmRunner(fix: ["atfTest"],
                              tests: ["atfTest": .fail(after: 5)])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["atfTest"])
        XCTAssertEqual(tests["atfTest"]?.runs.count, 6)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.status == .pass }.count, 5)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.xcStatus == .pass }.count, 5)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertNil(tests["atfTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["atfTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 5)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAttemptToFix }.count, 5)
        XCTAssertNil(tests["atfTest"]?.runs.last?.tags[DDTestTags.testHasFailedAllRetries])
        XCTAssertEqual(tests["atfTest"]?.runs.last?.tags[DDTestManagementTags.testAttemptToFixPassed], "false")
        XCTAssertEqual(tests["atfTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == nil
        }.count, 6)
        XCTAssertEqual(tests["atfTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["atfTest"]?.isSkipped, false)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["atfTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }

    func testTMSuppressesErrorForNonRetriableQuarantinedTest() async throws {
        let runner = tmRunner(quarantined: ["quarantinedTest"],
                              tests: ["quarantinedTest": .fail("Should fail", tags: .init(retriable: false))])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["quarantinedTest"])
        XCTAssertEqual(tests["quarantinedTest"]?.runs.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter { $0.xcStatus == .pass }.count, 1)
        XCTAssertNil(tests["quarantinedTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["quarantinedTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertEqual(tests["quarantinedTest"]?.runs.filter {
            $0.tags[DDTestTags.testFailureSuppressionReason] == DDTagValues.failureSuppressionReasonQuarantine
        }.count, 1)
        XCTAssertEqual(tests["quarantinedTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
    }

    func testTMDoesNotRetryNonRetriableAtfTest() async throws {
        let runner = tmRunner(fix: ["atfTest"],
                              tests: ["atfTest": .fail("Should fail", tags: .init(retriable: false))])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["atfTest"])
        XCTAssertEqual(tests["atfTest"]?.runs.count, 1)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["atfTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertNil(tests["atfTest"]?.runs.first?.tags[DDEfdTags.testIsRetry])
        XCTAssertNil(tests["atfTest"]?.runs.first?.tags[DDEfdTags.testRetryReason])
        XCTAssertNil(tests["atfTest"]?.runs.first?.tags[DDTestTags.testFailureSuppressionReason])
        XCTAssertNil(tests["atfTest"]?.runs.last?.tags[DDTestManagementTags.testAttemptToFixPassed])
        XCTAssertEqual(tests["atfTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
    }

    func tmAndEfdRunner(fix: [String] = [], disabled: [String] = [],
                        quarantined: [String] = [], known: [String],
                        tests: KeyValuePairs<String, Mocks.Runner.TestMethod>) -> Mocks.Runner
    {
        let runner = tmRunner(fix: fix, disabled: disabled, quarantined: quarantined, tests: tests)
        let efd = EarlyFlakeDetection(
            knownTests: KnownTests(tests: ["TMModule": ["TMSuite": known]]),
            slowTestRetries: .init(attrs: ["5s": 10, "30s": 5, "1m": 2, "5m": 1]),
            faultySessionThreshold: 30,
            log: Mocks.CatchLogger(isDebug: false))
        let knownFeature = KnownTests(tests: ["TMModule": ["TMSuite": known]])
        var features = runner.features.features
        features.insert(efd, at: features.count - 1)
        features.insert(knownFeature, at: features.count - 1)
        runner.features = features
        return runner
    }

    func tmAndTiaRunner(fix: [String] = [], disabled: [String] = [],
                        quarantined: [String] = [], skip: [String],
                        tests: KeyValuePairs<String, Mocks.Runner.TestMethod>) -> Mocks.Runner
    {
        let runner = tmRunner(fix: fix, disabled: disabled, quarantined: quarantined, tests: tests)
        let skipped = SkipTests(
            correlationId: "abacaba",
            tests: skip.map { .init(name: $0, suite: "TMSuite", configuration: ["test.bundle": "TMModule"]) })
        let tia = TestImpactAnalysis(tests: skipped, swiftTestingEnabled: false)
        var features = runner.features.features
        features.insert(tia, at: features.count - 1)
        runner.features = features
        return runner
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
        return Mocks.Runner(features: [tm, AdditionalTags()], tests: ["TMModule": ["TMSuite": .init(tests: tests)]])
    }
    
    func tmAndAtrRunner(fix: [String] = [], disabled: [String] = [],
                        quarantined: [String] = [],
                        tests: KeyValuePairs<String, Mocks.Runner.TestMethod>) -> Mocks.Runner
    {
        let runner = tmRunner(fix: fix, disabled: disabled, quarantined: quarantined, tests: tests)
        let atr = AutomaticTestRetries(failedTestRetriesCount: 5, failedTestTotalRetriesMax: 1000)
        var features = runner.features.features
        features.insert(atr, at: features.count - 1)
        runner.features = features
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
