/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting
@testable import EventsExporter

class TestImpactAnalysisTests: XCTestCase {
    func testTestImpactAnalysisSkipsTest() async throws {
        let (runner, tia, collector) = tiaRunner(skip: ["skipTest"],
                                                 tests: ["someTest": .fail("Always fails"),
                                                         "skipTest": .fail("Always fails")])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["skipTest"])
        XCTAssertEqual(tests["skipTest"]?.runs.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.status == .skip }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.xcStatus == .skip }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == "true" }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.first?.tags[DDTestTags.testSkipReason], "Skipped by Test Impact Analysis")
        XCTAssertEqual(tests["skipTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["skipTest"]?.isSkipped, true)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusSkip)
        XCTAssertEqual(tia.skippedCount, 1)
        
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 1)
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDTestTags.testSkipReason])
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
        XCTAssertEqual(collector.tests.count, 1) // someTest ran once; skipTest was skipped
    }

    func testTestImpactAnalysisDoesntSkipUnskippable() async throws {
        let (runner, tia, collector) = tiaRunner(skip: ["skipTest"],
                                         tests: ["someTest": .fail("Always fails"),
                                                 "skipTest": .fail("Always fails", tags: .init(skippable: false))])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["skipTest"])
        XCTAssertEqual(tests["skipTest"]?.runs.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == "true" }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == "true" }.count, 1)
        XCTAssertNil(tests["skipTest"]?.runs.first?.tags[DDTestTags.testSkipReason])
        XCTAssertEqual(tests["skipTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["skipTest"]?.isSkipped, false)
        XCTAssertEqual(tia.skippedCount, 0)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
        
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 1)
        XCTAssertNil(tests["someTest"]?.runs.first?.tags[DDTestTags.testSkipReason])
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusFail)
        XCTAssertEqual(collector.tests.count, 2) // both someTest and skipTest (unskippable) ran once each
    }

    // TIA + EFD
    func testTestImpactAnalysisSkipsEFDKnownTest() async throws {
        let (runner, tia, collector) = tiaAndEfdRunner(skip: ["skipTest"], known: ["skipTest"],
                                               tests: ["someTest": .failOddRuns(),
                                                       "skipTest": .fail("Always fails")])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["skipTest"])
        XCTAssertEqual(tests["skipTest"]?.runs.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.status == .skip }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.xcStatus == .skip }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == "true" }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.first?.tags[DDTestTags.testSkipReason], "Skipped by Test Impact Analysis")
        XCTAssertEqual(tests["skipTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["skipTest"]?.isSkipped, true)
        XCTAssertEqual(tia.skippedCount, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusSkip)
        
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 10)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 0)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 10)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 10)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 10)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == "true" }.count, 10)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 9)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonEarlyFlakeDetection }.count, 9)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkipReason] == nil }.count, 10)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
        XCTAssertEqual(collector.tests.count, 10) // someTest ran 10 times via EFD; skipTest was skipped
    }

    func testTestImpactAnalysisSkipsEFDUnknownTest() async throws {
        let (runner, tia, collector) = tiaAndEfdRunner(skip: ["skipTest"], known: [],
                                               tests: ["someTest": .failOddRuns(),
                                                       "skipTest": .fail("Always fails")])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["skipTest"])
        XCTAssertEqual(tests["skipTest"]?.runs.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.status == .skip }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.xcStatus == .skip }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == "true" }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == "true" }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.first?.tags[DDTestTags.testSkipReason], "Skipped by Test Impact Analysis")
        XCTAssertEqual(tests["skipTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["skipTest"]?.isSkipped, true)
        XCTAssertEqual(tia.skippedCount, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusSkip)
        
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 10)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 0)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 10)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 10)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 10)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == "true" }.count, 10)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 9)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonEarlyFlakeDetection }.count, 9)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkipReason] == nil }.count, 10)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
        XCTAssertEqual(collector.tests.count, 10) // someTest ran 10 times via EFD; skipTest was skipped
    }

    func testTestImpactAnalysisUnskippableEFDWorks() async throws {
        let (runner, tia, collector) = tiaAndEfdRunner(skip: ["skipTest"], known: [],
                                               tests: ["someTest": .failOddRuns(),
                                                       "skipTest": .failEvenRuns(tags: .init(skippable: false))])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["skipTest"])
        XCTAssertEqual(tests["skipTest"]?.runs.count, 10)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.status == .fail }.count, 5)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.xcStatus == .pass }.count, 10)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 10)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == "true" }.count, 10)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == "true" }.count, 10)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == "true" }.count, 10)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 9)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonEarlyFlakeDetection }.count, 9)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testSkipReason] == nil }.count, 10)
        XCTAssertEqual(tests["skipTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["skipTest"]?.isSkipped, false)
        XCTAssertEqual(tia.skippedCount, 0)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
        
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 10)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 5)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 0)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 10)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 10)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 10)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == "true" }.count, 10)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 9)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonEarlyFlakeDetection }.count, 9)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkipReason] == nil }.count, 10)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
        XCTAssertEqual(collector.tests.count, 20) // someTest 10 + skipTest (unskippable) 10 runs via EFD
    }

    // TIA + ATR
    func testTestImpactAnalysisAndATRWorksTogether() async throws {
        let (runner, tia, collector) = tiaAndAtrRunner(skip: ["skipTest"],
                                               tests: ["someTest": .fail(first: 3),
                                                       "skipTest": .fail("Always fails")])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["skipTest"])
        XCTAssertEqual(tests["skipTest"]?.runs.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.status == .skip }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.xcStatus == .skip }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == "true" }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.first?.tags[DDTestTags.testSkipReason], "Skipped by Test Impact Analysis")
        XCTAssertEqual(tests["skipTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["skipTest"]?.isSkipped, true)
        XCTAssertEqual(tia.skippedCount, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusSkip)
        
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 3)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .pass }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 0)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 3)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 3)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkipReason] == nil }.count, 4)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
        XCTAssertEqual(collector.tests.count, 4) // someTest ran 4 times via ATR; skipTest was skipped
    }

    func testTestImpactAnalysisAndATRWorksTogetherUnskippable() async throws {
        let (runner, tia, collector) = tiaAndAtrRunner(skip: ["skipTest"],
                                               tests: ["someTest": .fail(first: 3),
                                                       "skipTest": .fail(first: 4, tags: .init(skippable: false))])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["skipTest"])
        XCTAssertEqual(tests["skipTest"]?.runs.count, 5)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.status == .fail }.count, 4)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.xcStatus == .fail }.count, 0)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 5)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == "true" }.count, 5)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == "true" }.count, 5)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 4)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 4)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testSkipReason] == nil }.count, 5)
        XCTAssertEqual(tests["skipTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["skipTest"]?.isSkipped, false)
        XCTAssertEqual(tia.skippedCount, 0)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
        
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 3)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 0)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 3)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 3)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkipReason] == nil }.count, 4)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
        XCTAssertEqual(collector.tests.count, 9) // skipTest (unskippable) 5 runs + someTest 4 runs via ATR
    }

    // TIA + EFD + ATR
    func testTestImpactAnalysisSkipsEFDKnownTestAndATRRuns() async throws {
        let (runner, tia, collector) = tiaEfdAndAtrRunner(skip: ["skipTest"], known: ["skipTest", "knownTest"],
                                                  tests: ["unknownTest": .failOddRuns(),
                                                          "knownTest": .fail(first: 3),
                                                          "skipTest": .fail("Always fails")])
        let tests = try await extractTests(runner.run())
        XCTAssertNotNil(tests["skipTest"])
        XCTAssertEqual(tests["skipTest"]?.runs.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.status == .skip }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.xcStatus == .skip }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == "true" }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.first?.tags[DDTestTags.testSkipReason], "Skipped by Test Impact Analysis")
        XCTAssertEqual(tests["skipTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["skipTest"]?.isSkipped, true)
        XCTAssertEqual(tia.skippedCount, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusSkip)
        
        // EFD works
        XCTAssertNotNil(tests["unknownTest"])
        XCTAssertEqual(tests["unknownTest"]?.runs.count, 10)
        XCTAssertEqual(tests["unknownTest"]?.runs.filter { $0.status == .fail }.count, 5)
        XCTAssertEqual(tests["unknownTest"]?.runs.filter { $0.xcStatus == .fail }.count, 0)
        XCTAssertEqual(tests["unknownTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 10)
        XCTAssertEqual(tests["unknownTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 10)
        XCTAssertEqual(tests["unknownTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 10)
        XCTAssertEqual(tests["unknownTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == "true" }.count, 10)
        XCTAssertEqual(tests["unknownTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 9)
        XCTAssertEqual(tests["unknownTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonEarlyFlakeDetection }.count, 9)
        XCTAssertEqual(tests["unknownTest"]?.runs.filter { $0.tags[DDTestTags.testSkipReason] == nil }.count, 10)
        XCTAssertEqual(tests["unknownTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["unknownTest"]?.isSkipped, false)
        XCTAssertEqual(tests["unknownTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["unknownTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
        
        // ATR works
        XCTAssertNotNil(tests["knownTest"])
        XCTAssertEqual(tests["knownTest"]?.runs.count, 4)
        XCTAssertEqual(tests["knownTest"]?.runs.filter { $0.status == .fail }.count, 3)
        XCTAssertEqual(tests["knownTest"]?.runs.filter { $0.xcStatus == .fail }.count, 0)
        XCTAssertEqual(tests["knownTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 4)
        XCTAssertEqual(tests["knownTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 4)
        XCTAssertEqual(tests["knownTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 4)
        XCTAssertEqual(tests["knownTest"]?.runs.filter { $0.tags[DDTestTags.testIsNew] == nil }.count, 4)
        XCTAssertEqual(tests["knownTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 3)
        XCTAssertEqual(tests["knownTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 3)
        XCTAssertEqual(tests["knownTest"]?.runs.filter { $0.tags[DDTestTags.testSkipReason] == nil }.count, 4)
        XCTAssertEqual(tests["knownTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["knownTest"]?.isSkipped, false)
        XCTAssertEqual(tests["knownTest"]?.runs.filter { $0.tags[DDTestTags.testFinalStatus] != nil }.count, 1)
        XCTAssertEqual(tests["knownTest"]?.runs.last?.tags[DDTestTags.testFinalStatus], DDTagValues.statusPass)
        XCTAssertEqual(collector.tests.count, 14) // unknownTest 10 + knownTest 4; skipTest was skipped
    }

    func tiaRunner(skip: [String], tests: KeyValuePairs<String, Mocks.Runner.TestMethod>) -> (Mocks.Runner, TestImpactAnalysis, Mocks.CoverageCollector) {
        let skipped = SkipTests(correlationId: "abacaba",
                                tests: skip.map { .init(name: $0,
                                                        suite: "TIASuite",
                                                        configuration: ["test.bundle": "TIAModule"]) })
        let collector = Mocks.CoverageCollector()
        let tia = TestImpactAnalysis(tests: skipped, coverage: collector, swiftTestingEnabled: false)
        return (Mocks.Runner(features: [tia, AdditionalTags()], tests: ["TIAModule": ["TIASuite": .init(tests: tests)]]), tia, collector)
    }
    
    func tiaAndEfdRunner(skip: [String], known: [String], tests: KeyValuePairs<String, Mocks.Runner.TestMethod>) -> (Mocks.Runner, TestImpactAnalysis, Mocks.CoverageCollector) {
        let runner = tiaRunner(skip: skip, tests: tests)
        let efd = EarlyFlakeDetection(
            knownTests: KnownTests(tests: ["TIAModule": ["TIASuite": known]]),
            slowTestRetries: .init(attrs: ["5s": 10, "30s": 5, "1m": 2, "5m": 1]),
            faultySessionThreshold: 30,
            log: Mocks.CatchLogger(isDebug: false)
        )
        let knownFeature = KnownTests(tests: ["TIAModule": ["TIASuite": known]])
        var features = runner.0.features.features
        features.insert(efd, at: features.count - 1)
        features.insert(knownFeature, at: features.count - 1)
        runner.0.features = features
        return runner
    }
    
    func tiaAndAtrRunner(skip: [String], tests: KeyValuePairs<String, Mocks.Runner.TestMethod>) -> (Mocks.Runner, TestImpactAnalysis, Mocks.CoverageCollector) {
        let runner = tiaRunner(skip: skip, tests: tests)
        let atr = AutomaticTestRetries(failedTestRetriesCount: 5, failedTestTotalRetriesMax: 1000)
        var features = runner.0.features.features
        features.insert(atr, at: features.count - 1)
        runner.0.features = features
        return runner
    }
    
    func tiaEfdAndAtrRunner(skip: [String], known: [String], tests: KeyValuePairs<String, Mocks.Runner.TestMethod>) -> (Mocks.Runner, TestImpactAnalysis, Mocks.CoverageCollector) {
        let runner = tiaAndEfdRunner(skip: skip, known: known, tests: tests)
        let atr = AutomaticTestRetries(failedTestRetriesCount: 5, failedTestTotalRetriesMax: 1000)
        var features = runner.0.features.features
        features.insert(atr, at: features.count - 2)
        runner.0.features = features
        return runner
    }
    
    func extractTests(_ session: Mocks.Session) throws -> [String: Mocks.Group] {
        guard let suite = session["TIAModule"]?["TIASuite"] else {
            throw InternalError(description: "Can't get TIAModule and TIASuite")
        }
        return suite.tests
    }
}
