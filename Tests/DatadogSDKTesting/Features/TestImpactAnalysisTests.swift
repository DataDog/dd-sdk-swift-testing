/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting
@testable import EventsExporter

class TestImpactAnalysisTests: XCTestCase {
    func testTestImpactAnalysisSkipsTest() throws {
        let (runner, tia, _) = tiaRunner(skip: ["skipTest"],
                                         tests: ["someTest": .fail("Always fails"),
                                                 "skipTest": .fail("Always fails")])
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["skipTest"])
        XCTAssertEqual(tests["skipTest"]?.runs.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.status == .skip }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.xcStatus == .skip }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == "true" }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["skipTest"]?.isSkipped, true)
        XCTAssertEqual(tia.skippedCount, 1)
        
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
    }
    
    func testTestImpactAnalysisDoesntSkipUnskippable() throws {
        let (runner, tia, _) = tiaRunner(skip: ["skipTest"],
                                         tests: ["someTest": .fail("Always fails"),
                                                 "skipTest": .fail("Always fails", unskippable: true)])
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["skipTest"])
        XCTAssertEqual(tests["skipTest"]?.runs.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == "true" }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == "true" }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["skipTest"]?.isSkipped, false)
        XCTAssertEqual(tia.skippedCount, 0)
        
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 1)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
    }
    
    // TIA + EFD
    func testTestImpactAnalysisSkipsEFDKnownTest() throws {
        let (runner, tia, _) = tiaAndEfdRunner(skip: ["skipTest"], known: ["skipTest"],
                                               tests: ["someTest": .failOddRuns(),
                                                       "skipTest": .fail("Always fails")])
        let tests = try extractTests(runner.run())
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
        XCTAssertEqual(tests["skipTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["skipTest"]?.isSkipped, true)
        XCTAssertEqual(tia.skippedCount, 1)
        
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
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
    }
    
    func testTestImpactAnalysisSkipsEFDUnknownTest() throws {
        let (runner, tia, _) = tiaAndEfdRunner(skip: ["skipTest"], known: [],
                                               tests: ["someTest": .failOddRuns(),
                                                       "skipTest": .fail("Always fails")])
        let tests = try extractTests(runner.run())
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
        XCTAssertEqual(tests["skipTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["skipTest"]?.isSkipped, true)
        XCTAssertEqual(tia.skippedCount, 1)
        
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
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
    }
    
    func testTestImpactAnalysisUnskippableEFDWorks() throws {
        let (runner, tia, _) = tiaAndEfdRunner(skip: ["skipTest"], known: [],
                                               tests: ["someTest": .failOddRuns(),
                                                       "skipTest": .failEvenRuns(unskippable: true)])
        let tests = try extractTests(runner.run())
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
        XCTAssertEqual(tests["skipTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["skipTest"]?.isSkipped, false)
        XCTAssertEqual(tia.skippedCount, 0)
        
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
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
    }
    
    // TIA + ATR
    func testTestImpactAnalysisAndATRWorksTogether() throws {
        let (runner, tia, _) = tiaAndAtrRunner(skip: ["skipTest"],
                                               tests: ["someTest": .fail(first: 3),
                                                       "skipTest": .fail("Always fails")])
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["skipTest"])
        XCTAssertEqual(tests["skipTest"]?.runs.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.status == .skip }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.xcStatus == .skip }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == "true" }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == nil }.count, 1)
        XCTAssertEqual(tests["skipTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["skipTest"]?.isSkipped, true)
        XCTAssertEqual(tia.skippedCount, 1)
        
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
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
    }
    
    func testTestImpactAnalysisAndATRWorksTogetherUnskippable() throws {
        let (runner, tia, _) = tiaAndAtrRunner(skip: ["skipTest"],
                                               tests: ["someTest": .fail(first: 3),
                                                       "skipTest": .fail(first: 4, unskippable: true)])
        let tests = try extractTests(runner.run())
        XCTAssertNotNil(tests["skipTest"])
        XCTAssertEqual(tests["skipTest"]?.runs.count, 5)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.status == .fail }.count, 4)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.xcStatus == .fail }.count, 0)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 5)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == "true" }.count, 5)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == "true" }.count, 5)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 4)
        XCTAssertEqual(tests["skipTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 4)
        XCTAssertEqual(tests["skipTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["skipTest"]?.isSkipped, false)
        XCTAssertEqual(tia.skippedCount, 0)
        
        XCTAssertNotNil(tests["someTest"])
        XCTAssertEqual(tests["someTest"]?.runs.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.status == .fail }.count, 3)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.xcStatus == .fail }.count, 0)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDTestTags.testSkippedByITR] == nil }.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrUnskippable] == nil }.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDItrTags.itrForcedRun] == nil }.count, 4)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testIsRetry] == "true" }.count, 3)
        XCTAssertEqual(tests["someTest"]?.runs.filter { $0.tags[DDEfdTags.testRetryReason] == DDTagValues.retryReasonAutoTestRetry }.count, 3)
        XCTAssertEqual(tests["someTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["someTest"]?.isSkipped, false)
    }
    
    // TIA + EFD + ATR
    func testTestImpactAnalysisSkipsEFDKnownTestAndATRRuns() throws {
        let (runner, tia, _) = tiaEfdAndAtrRunner(skip: ["skipTest"], known: ["skipTest", "knownTest"],
                                                  tests: ["unknownTest": .failOddRuns(),
                                                          "knownTest": .fail(first: 3),
                                                          "skipTest": .fail("Always fails")])
        let tests = try extractTests(runner.run())
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
        XCTAssertEqual(tests["skipTest"]?.isSucceeded, false)
        XCTAssertEqual(tests["skipTest"]?.isSkipped, true)
        XCTAssertEqual(tia.skippedCount, 1)
        
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
        XCTAssertEqual(tests["unknownTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["unknownTest"]?.isSkipped, false)
        
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
        XCTAssertEqual(tests["knownTest"]?.isSucceeded, true)
        XCTAssertEqual(tests["knownTest"]?.isSkipped, false)
    }
    
    func tiaRunner(skip: [String], tests: KeyValuePairs<String, Mocks.Runner.TestMethod>) -> (Mocks.Runner, TestImpactAnalysis, Mocks.CoverageCollector) {
        let skipped = SkipTests(correlationId: "abacaba", tests: skip.map { .init(name: $0, suite: "TIASuite") })
        let collector = Mocks.CoverageCollector()
        let tia = TestImpactAnalysis(tests: skipped, coverage: Mocks.CoverageCollector())
        return (Mocks.Runner(features: [tia], tests: ["TIAModule": ["TIASuite": tests]]), tia, collector)
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
        runner.0.features.append(efd)
        runner.0.features.append(knownFeature)
        return runner
    }
    
    func tiaAndAtrRunner(skip: [String], tests: KeyValuePairs<String, Mocks.Runner.TestMethod>) -> (Mocks.Runner, TestImpactAnalysis, Mocks.CoverageCollector) {
        let runner = tiaRunner(skip: skip, tests: tests)
        let atr = AutomaticTestRetries(failedTestRetriesCount: 5, failedTestTotalRetriesMax: 1000)
        runner.0.features.append(atr)
        return runner
    }
    
    func tiaEfdAndAtrRunner(skip: [String], known: [String], tests: KeyValuePairs<String, Mocks.Runner.TestMethod>) -> (Mocks.Runner, TestImpactAnalysis, Mocks.CoverageCollector) {
        let runner = tiaAndEfdRunner(skip: skip, known: known, tests: tests)
        let atr = AutomaticTestRetries(failedTestRetriesCount: 5, failedTestTotalRetriesMax: 1000)
        runner.0.features.insert(atr, at: runner.0.features.count - 1)
        return runner
    }
    
    func extractTests(_ session: Mocks.Session) throws -> [String: Mocks.Group] {
        guard let suite = session["TIAModule"]?["TIASuite"] else {
            throw InternalError(description: "Can't get TIAModule and TIASuite")
        }
        return suite.tests
    }
}
