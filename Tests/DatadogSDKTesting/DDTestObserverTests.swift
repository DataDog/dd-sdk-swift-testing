/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
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
        DDEnvironmentValues.environment[ConfigurationValues.DD_API_KEY.rawValue] = "fakeKey"
        DDEnvironmentValues.environment["DD_DISABLE_TEST_INSTRUMENTING"] = "1"
        DDTestMonitor.env = DDEnvironmentValues()
        testObserver = DDTestObserver()
        testObserver.startObserving()
        theSuite.setValue([self], forKey: "_mutableTests")
    }

    override func tearDown() {
        XCTestObservationCenter.shared.removeTestObserver(testObserver)
        testObserver = nil
        XCTAssertNil(DDTracer.activeSpan)
    }

    func testWhenTestBundleWillStartIsCalled_testBundleNameIsSet() throws {
        testObserver.testBundleWillStart(Bundle.main)
        let bundleName = try XCTUnwrap(testObserver.module?.bundleName)
        XCTAssertFalse(bundleName.isEmpty)
        testObserver.testBundleDidFinish(Bundle.main)
    }

    func testWhenTestCaseWillStartIsCalled_testSpanIsCreated() {
        testObserver.testBundleWillStart(Bundle.main)
        testObserver.testSuiteWillStart(theSuite)
        testObserver.testCaseWillStart(self)

        let testName = "testWhenTestCaseWillStartIsCalled_testSpanIsCreated"
        let testSuite = "DDTestObserverTests"
        //let testBundle = testObserver.module?.bundleName
        let deviceModel = PlatformUtils.getDeviceModel()
        let deviceVersion = PlatformUtils.getDeviceVersion()
        let span = OpenTelemetry.instance.contextProvider.activeSpan as! RecordEventsReadableSpan
        let spanData = span.toSpanData()

        XCTAssertEqual(spanData.name, "XCTest.test")
        XCTAssertEqual(spanData.attributes[DDGenericTags.language]?.description, "swift")
        XCTAssertEqual(spanData.attributes[DDGenericTags.type]?.description, DDTagValues.typeTest)
        XCTAssertEqual(spanData.attributes[DDGenericTags.resource]?.description, "\(testSuite).\(testName)")
        XCTAssertEqual(spanData.attributes[DDTestTags.testName]?.description, testName)
        XCTAssertEqual(spanData.attributes[DDTestTags.testSuite]?.description, testSuite)
        XCTAssertEqual(spanData.attributes[DDTestTags.testFramework]?.description, "XCTest")
        XCTAssertEqual(spanData.attributes[DDTestTags.testType]?.description, DDTagValues.typeTest)
        XCTAssertEqual(spanData.attributes[DDOSTags.osArchitecture]?.description, PlatformUtils.getPlatformArchitecture())
        XCTAssertEqual(spanData.attributes[DDOSTags.osPlatform]?.description, PlatformUtils.getRunningPlatform())
        XCTAssertEqual(spanData.attributes[DDOSTags.osVersion]?.description, deviceVersion)
        XCTAssertEqual(spanData.attributes[DDDeviceTags.deviceModel]?.description, deviceModel)
        XCTAssertEqual(spanData.attributes[DDDeviceTags.deviceName]?.description, PlatformUtils.getDeviceName())
        XCTAssertEqual(spanData.attributes[DDRuntimeTags.runtimeName]?.description, "Xcode")
        XCTAssertEqual(spanData.attributes[DDRuntimeTags.runtimeVersion]?.description, PlatformUtils.getXcodeVersion())
        XCTAssertNotNil(spanData.attributes[DDCITags.ciWorkspacePath])
        XCTAssertNotNil(spanData.attributes[DDUISettingsTags.uiSettingsLocalization])

        testObserver.testCaseDidFinish(self)
        testObserver.testSuiteDidFinish(theSuite)
        testObserver.testBundleDidFinish(Bundle.main)
    }

    func testWhenTestCaseDidFinishIsCalled_testStatusIsSet() {
        testObserver.testBundleWillStart(Bundle.main)
        testObserver.testSuiteWillStart(theSuite)
        testObserver.testCaseWillStart(self)

        let testSpan = OpenTelemetry.instance.contextProvider.activeSpan as! RecordEventsReadableSpan
        var spanData = testSpan.toSpanData()
        XCTAssertNil(spanData.attributes[DDTestTags.testStatus])

        testObserver.testCaseDidFinish(self)

        spanData = testSpan.toSpanData()
        XCTAssertNotNil(spanData.attributes[DDTestTags.testStatus])

        testObserver.testSuiteDidFinish(theSuite)
        testObserver.testBundleDidFinish(Bundle.main)
    }

    #if swift(>=5.3)
        func testWhenTestCaseDidRecordIssueIsCalled_testStatusIsSet() {
            testObserver.testBundleWillStart(Bundle.main)
            testObserver.testSuiteWillStart(theSuite)
            testObserver.testCaseWillStart(self)
            let issue = XCTIssue(type: .assertionFailure, compactDescription: "descrip", detailedDescription: nil, sourceCodeContext: XCTSourceCodeContext(), associatedError: nil, attachments: [])
            testObserver.testCase(self, didRecord: issue)

            let testSpan = OpenTelemetry.instance.contextProvider.activeSpan as! RecordEventsReadableSpan
            testObserver.testCaseDidFinish(self)
            let spanData = testSpan.toSpanData()

            XCTAssertNotNil(spanData.attributes[DDTags.errorType])
            XCTAssertNotNil(spanData.attributes[DDTags.errorMessage])
            XCTAssertNil(spanData.attributes[DDTags.errorStack])

            testObserver.testSuiteDidFinish(theSuite)
            testObserver.testBundleDidFinish(Bundle.main)
        }
    #else
        func testWhenTestCaseDidFailWithDescriptionIsCalled_testStatusIsSet() {
            testObserver.testBundleWillStart(Bundle.main)
            testObserver.testSuiteWillStart(theSuite)
            testObserver.testCaseWillStart(self)
            testObserver.testCase(self, didFailWithDescription: "descrip", inFile: "samplefile", atLine: 239)

            let testSpan = OpenTelemetry.instance.contextProvider.activeSpan as! RecordEventsReadableSpan
            let spanData = testSpan.toSpanData()

            XCTAssertNotNil(spanData.attributes[DDTags.errorType])
            XCTAssertNotNil(spanData.attributes[DDTags.errorMessage])
            XCTAssertNil(spanData.attributes[DDTags.errorStack])

            testObserver.testCaseDidFinish(self)
            testObserver.testSuiteDidFinish(theSuite)
            testObserver.testBundleDidFinish(Bundle.main)
        }
    #endif

    func testWhenTestCaseDidFinishIsCalledAndTheTestIsABenchmark_benchmarkTagsAreAdded() {
        testObserver.testBundleWillStart(Bundle.main)
        testObserver.testSuiteWillStart(theSuite)
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

        testObserver.testSuiteDidFinish(theSuite)
        testObserver.testBundleDidFinish(Bundle.main)
    }

    #if swift(>=5.3)
        func testWhenTestCaseDidRecordIssueIsCalledTwice_twoErrorsAppear() {
            testObserver.testBundleWillStart(Bundle.main)
            testObserver.testSuiteWillStart(theSuite)
            testObserver.testCaseWillStart(self)

            let error1Text = "error1"
            let error2Text = "error2"
            let issue = XCTIssue(type: .assertionFailure, compactDescription: error1Text, detailedDescription: nil, sourceCodeContext: XCTSourceCodeContext(), associatedError: nil, attachments: [])
            testObserver.testCase(self, didRecord: issue)

            let issue2 = XCTIssue(type: .assertionFailure, compactDescription: error2Text, detailedDescription: nil, sourceCodeContext: XCTSourceCodeContext(), associatedError: nil, attachments: [])
            testObserver.testCase(self, didRecord: issue2)

            let testSpan = OpenTelemetry.instance.contextProvider.activeSpan as! RecordEventsReadableSpan
            testObserver.testCaseDidFinish(self)
            let spanData = testSpan.toSpanData()

            XCTAssertTrue(spanData.attributes[DDTags.errorMessage]?.description.contains(exactWord: error1Text) ?? false)
            XCTAssertTrue(spanData.attributes[DDTags.errorMessage]?.description.contains(exactWord: error2Text) ?? false)

            testObserver.testSuiteDidFinish(theSuite)
            testObserver.testBundleDidFinish(Bundle.main)
        }
    #endif
}
