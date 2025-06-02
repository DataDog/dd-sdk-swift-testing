/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest

internal class DDTestObserverTests: XCTestCase {
    var testObserver: DDTestObserver!

    let theSuite = XCTestSuite(name: "DDTestObserverTests")

    override func setUp() {
        XCTAssertNil(DDTracer.activeSpan)
        DDTestMonitor._env_recreate(env: ["DD_API_KEY": "fakeToken", "DD_DISABLE_TEST_INSTRUMENTING": "1"])
        testObserver = DDTestObserver()
        testObserver.start()
        theSuite.setValue([self], forKey: "_mutableTests")
    }

    override func tearDown() {
        testObserver.stop()
        testObserver = nil
        DDTestMonitor._env_recreate()
        XCTAssertNil(DDTracer.activeSpan)
    }

    func testWhenTestBundleWillStartIsCalled_testBundleNameIsSet() throws {
        testObserver.testBundleWillStart(Bundle.main)
        guard case .module(let module) = testObserver.state else {
            XCTFail("Bad observer state: \(testObserver.state)")
            return
        }
        XCTAssertFalse(module.name.isEmpty)
        testObserver.testBundleDidFinish(Bundle.main)
    }

    func testWhenTestCaseWillStartIsCalled_testSpanIsCreated() {
        let group = DDXCTestRetryGroup(for: self)
        testObserver.testBundleWillStart(Bundle.main)
        testObserver.testSuiteWillStart(theSuite)
        testObserver.testRetryGroupWillStart(group)
        testObserver.testCaseWillStart(self)

        let testName = "testWhenTestCaseWillStartIsCalled_testSpanIsCreated"
        let testSuite = "DDTestObserverTests"
        //let testBundle = testObserver.module?.bundleName
        let span = OpenTelemetry.instance.contextProvider.activeSpan as! RecordEventsReadableSpan
        
        let spanData = span.toSpanData()

        XCTAssertEqual(spanData.name, "XCTest.test")
        XCTAssertEqual(spanData.attributes[DDGenericTags.type]?.description, DDTagValues.typeTest)
        XCTAssertEqual(spanData.attributes[DDGenericTags.resource]?.description, "\(testSuite).\(testName)")
        XCTAssertEqual(spanData.attributes[DDTestTags.testName]?.description, testName)
        XCTAssertEqual(spanData.attributes[DDTestTags.testSuite]?.description, testSuite)
        XCTAssertEqual(spanData.attributes[DDTestTags.testFramework]?.description, "XCTest")
        XCTAssertEqual(spanData.attributes[DDTestTags.testType]?.description, DDTagValues.typeTest)
        XCTAssertEqual(spanData.attributes[DDHostTags.hostVCPUCount]?.description, String(Double(PlatformUtils.getCpuCount())))

        testObserver.testCaseDidFinish(self)
        testObserver.testRetryGroupDidFinish(group)
        testObserver.testSuiteDidFinish(theSuite)
        testObserver.testBundleDidFinish(Bundle.main)
    }

    func testWhenTestCaseDidFinishIsCalled_testStatusIsSet() {
        let group = DDXCTestRetryGroup(for: self)
        testObserver.testBundleWillStart(Bundle.main)
        testObserver.testSuiteWillStart(theSuite)
        testObserver.testRetryGroupWillStart(group)
        testObserver.testCaseWillStart(self)

        let testSpan = OpenTelemetry.instance.contextProvider.activeSpan as! RecordEventsReadableSpan
        var spanData = testSpan.toSpanData()
        XCTAssertNil(spanData.attributes[DDTestTags.testStatus])

        testObserver.testCaseDidFinish(self)

        spanData = testSpan.toSpanData()
        XCTAssertNotNil(spanData.attributes[DDTestTags.testStatus])

        testObserver.testRetryGroupDidFinish(group)
        testObserver.testSuiteDidFinish(theSuite)
        testObserver.testBundleDidFinish(Bundle.main)
    }

    
    func testWhenTestCaseDidRecordIssueIsCalled_testStatusIsSet() {
        let group = DDXCTestRetryGroup(for: self)
        testObserver.testBundleWillStart(Bundle.main)
        testObserver.testSuiteWillStart(theSuite)
        testObserver.testRetryGroupWillStart(group)
        testObserver.testCaseWillStart(self)
        let issue = XCTIssue(type: .assertionFailure, compactDescription: "descrip", detailedDescription: nil, sourceCodeContext: XCTSourceCodeContext(), associatedError: nil, attachments: [])
        testObserver.testCaseRetry(self, willRecord: issue)

        let testSpan = OpenTelemetry.instance.contextProvider.activeSpan as! RecordEventsReadableSpan
        testObserver.testCaseDidFinish(self)
        let spanData = testSpan.toSpanData()

        XCTAssertNotNil(spanData.attributes[DDTags.errorType])
        XCTAssertNotNil(spanData.attributes[DDTags.errorMessage])
        XCTAssertNil(spanData.attributes[DDTags.errorStack])

        testObserver.testRetryGroupDidFinish(group)
        testObserver.testSuiteDidFinish(theSuite)
        testObserver.testBundleDidFinish(Bundle.main)
    }

    func testWhenTestCaseDidFinishIsCalledAndTheTestIsABenchmark_benchmarkTagsAreAdded() {
        let group = DDXCTestRetryGroup(for: self)
        testObserver.testBundleWillStart(Bundle.main)
        testObserver.testSuiteWillStart(theSuite)
        testObserver.testRetryGroupWillStart(group)
        testObserver.testCaseWillStart(self)
        let testSpan = OpenTelemetry.instance.contextProvider.activeSpan as! RecordEventsReadableSpan
        let perfMetric = XCTPerformanceMetric.wallClockTime
        self.setValue([perfMetric], forKey: "_activePerformanceMetricIDs")
        self.setValue([perfMetric: ["measurements": [1, 2, 3, 4, 5]]], forKey: "_perfMetricsForID")

        testObserver.testCaseDidFinish(self)

        let spanData = testSpan.toSpanData()
        XCTAssertEqual(spanData.attributes[DDTestTags.testType]?.description, DDTagValues.typeBenchmark)

        let measure = DDBenchmarkTags.benchmark + "." + DDBenchmarkMeasuresTags.duration + "."
        XCTAssertEqual(spanData.attributes[measure + DDBenchmarkTags.benchmarkMean]?.description, "3000000000.0")
        XCTAssertEqual(spanData.attributes[measure + DDBenchmarkTags.statisticsN]?.description, "5")
        XCTAssertEqual(spanData.attributes[measure + DDBenchmarkTags.statisticsMin]?.description, "1000000000.0")
        XCTAssertEqual(spanData.attributes[measure + DDBenchmarkTags.statisticsMax]?.description, "5000000000.0")
        XCTAssertEqual(spanData.attributes[measure + DDBenchmarkTags.statisticsMedian]?.description, "3000000000.0")

        self.setValue(nil, forKey: "_activePerformanceMetricIDs")
        self.setValue(nil, forKey: "_perfMetricsForID")

        testObserver.testRetryGroupDidFinish(group)
        testObserver.testSuiteDidFinish(theSuite)
        testObserver.testBundleDidFinish(Bundle.main)
    }


    func testWhenTestCaseDidRecordIssueIsCalledTwice_twoErrorsAppear() {
        let group = DDXCTestRetryGroup(for: self)
        testObserver.testBundleWillStart(Bundle.main)
        testObserver.testSuiteWillStart(theSuite)
        testObserver.testRetryGroupWillStart(group)
        testObserver.testCaseWillStart(self)

        let error1Text = "error1"
        let error2Text = "error2"
        let issue = XCTIssue(type: .assertionFailure, compactDescription: error1Text, detailedDescription: nil, sourceCodeContext: XCTSourceCodeContext(), associatedError: nil, attachments: [])
        testObserver.testCaseRetry(self, willRecord: issue)

        let issue2 = XCTIssue(type: .assertionFailure, compactDescription: error2Text, detailedDescription: nil, sourceCodeContext: XCTSourceCodeContext(), associatedError: nil, attachments: [])
        testObserver.testCaseRetry(self, willRecord: issue2)

        let testSpan = OpenTelemetry.instance.contextProvider.activeSpan as! RecordEventsReadableSpan
        testObserver.testCaseDidFinish(self)
        let spanData = testSpan.toSpanData()

        XCTAssertTrue(spanData.attributes[DDTags.errorMessage]?.description.contains(exactWord: error1Text) ?? false)
        XCTAssertTrue(spanData.attributes[DDTags.errorMessage]?.description.contains(exactWord: error2Text) ?? false)

        testObserver.testRetryGroupDidFinish(group)
        testObserver.testSuiteDidFinish(theSuite)
        testObserver.testBundleDidFinish(Bundle.main)
    }
}
