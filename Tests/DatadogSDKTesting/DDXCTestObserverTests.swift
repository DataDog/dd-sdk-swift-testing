/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest

// MARK: - Tests

internal class DDXCTestObserverTests: XCTestCase {
    var testObserver: DDXCTestObserver!
    var session: SessionManager!

    let theSuite = XCTestSuite(name: "DDTestObserverTests")

    override func setUp() {
        XCTAssertNil(DDTracer.activeSpan)
        DDTestMonitor._env_recreate(env: ["DD_API_KEY": "fakeToken",
                                          "DD_DISABLE_TEST_INSTRUMENTING": "1",
                                          "DD_DISABLE_CRASH_HANDLER": "1"])
        session = SessionManager(log: Mocks.CatchLogger(isDebug: true),
                                 provider: Session.Provider(), observer: nil)
        testObserver = DDXCTestObserver(session: session, log: Mocks.CatchLogger(isDebug: true))
        theSuite.setValue([self], forKey: "_mutableTests")
    }

    override func tearDown() {
        XCTAssertNil(testObserver)
        DDTestMonitor.removeTestMonitor()
        DDTestMonitor._env_recreate()
        XCTAssertNil(DDTracer.activeSpan)
    }

    func testWhenTestBundleWillStartIsCalled_testBundleNameIsSet() async throws {
        testObserver.testBundleWillStart(Bundle.main)
        guard case .module(let module, _) = testObserver.state else {
            XCTFail("Bad observer state: \(testObserver.state)")
            return
        }
        XCTAssertFalse(module.name.isEmpty)
        testObserver.testBundleDidFinish(Bundle.main)
        await destroyObserver()
    }

    func testWhenTestCaseWillStartIsCalled_testSpanIsCreated() async {
        let group = DDXCTestRetryGroup(for: self, observer: testObserver)
        testObserver.testBundleWillStart(Bundle.main)
        testObserver.testSuiteWillStart(theSuite)
        testObserver.testRetryGroupWillStart(group)

        let testName = "testWhenTestCaseWillStartIsCalled_testSpanIsCreated"
        let testSuite = "DDTestObserverTests"

        let spanData = group.context.suite.withActiveTest(named: self.testId.test) { test in
            let originalRun = self.testRun
            let mockRun = MockXCTestCaseRetryRun(ddTest: test, group: group, xcTest: self)
            self.setValue(mockRun, forKey: "testRun")

            testObserver.testCaseWillStart(self)

            let span = OpenTelemetry.instance.contextProvider.activeSpan as! SpanSdk

            testObserver.testCaseDidFinish(self)
            self.setValue(originalRun, forKey: "testRun")
            return span.toSpanData()
        }

        testObserver.testRetryGroupDidFinish(group)
        testObserver.testSuiteDidFinish(theSuite)
        testObserver.testBundleDidFinish(Bundle.main)
        await destroyObserver()

        XCTAssertEqual(spanData.name, "XCTest.test")
        XCTAssertEqual(spanData.attributes[DDGenericTags.type]?.description, DDTagValues.typeTest)
        XCTAssertEqual(spanData.attributes[DDGenericTags.resource]?.description, "\(testSuite).\(testName)")
        XCTAssertEqual(spanData.attributes[DDTestTags.testName]?.description, testName)
        XCTAssertEqual(spanData.attributes[DDTestTags.testSuite]?.description, testSuite)
        XCTAssertEqual(spanData.attributes[DDTestTags.testFramework]?.description, "XCTest")
        XCTAssertEqual(spanData.attributes[DDTestTags.testFrameworkVersion]?.description, PlatformUtils.getXCTestVersion())
        XCTAssertEqual(spanData.attributes[DDTestTags.testType]?.description, DDTagValues.typeTest)
        XCTAssertEqual(spanData.attributes[DDHostTags.hostVCPUCount]?.description, String(Double(PlatformUtils.getCpuCount())))
    }

    func testWhenTestCaseDidFinishIsCalled_testStatusIsSet() async {
        let group = DDXCTestRetryGroup(for: self, observer: testObserver)
        testObserver.testBundleWillStart(Bundle.main)
        testObserver.testSuiteWillStart(theSuite)
        testObserver.testRetryGroupWillStart(group)

        var statusBefore: AttributeValue? = nil
     
        let spanData = group.context.suite.withActiveTest(named: self.testId.test) { test in
            let originalRun = self.testRun
            let mockRun = MockXCTestCaseRetryRun(ddTest: test, group: group, xcTest: self)
            self.setValue(mockRun, forKey: "testRun")

            testObserver.testCaseWillStart(self)

            let testSpan = OpenTelemetry.instance.contextProvider.activeSpan as! SpanSdk
            statusBefore = testSpan.toSpanData().attributes[DDTestTags.testStatus]

            testObserver.testCaseDidFinish(self)
            
            self.setValue(originalRun, forKey: "testRun")
            return testSpan.toSpanData()
        }

        testObserver.testRetryGroupDidFinish(group)
        testObserver.testSuiteDidFinish(theSuite)
        testObserver.testBundleDidFinish(Bundle.main)
        await destroyObserver()

        XCTAssertNil(statusBefore)
        XCTAssertNotNil(spanData.attributes[DDTestTags.testStatus])
    }

    func testWhenTestCaseDidRecordIssueIsCalled_testStatusIsSet() async {
        let group = DDXCTestRetryGroup(for: self, observer: testObserver)
        testObserver.testBundleWillStart(Bundle.main)
        testObserver.testSuiteWillStart(theSuite)
        testObserver.testRetryGroupWillStart(group)

        let spanData = group.context.suite.withActiveTest(named: self.testId.test) { test in
            let originalRun = self.testRun
            let mockRun = MockXCTestCaseRetryRun(ddTest: test, group: group, xcTest: self)
            self.setValue(mockRun, forKey: "testRun")

            testObserver.testCaseWillStart(self)

            let issue = XCTIssue(type: .assertionFailure, compactDescription: "descrip",
                                 detailedDescription: nil, sourceCodeContext: XCTSourceCodeContext(),
                                 associatedError: nil, attachments: [])
            mockRun.addFailure(issue)
            testObserver.testCase(self, didRecord: issue)

            let testSpan = OpenTelemetry.instance.contextProvider.activeSpan as! SpanSdk
            testObserver.testCaseDidFinish(self)
            self.setValue(originalRun, forKey: "testRun")
            return testSpan.toSpanData()
        }

        testObserver.testRetryGroupDidFinish(group)
        testObserver.testSuiteDidFinish(theSuite)
        testObserver.testBundleDidFinish(Bundle.main)
        await destroyObserver()

        XCTAssertNotNil(spanData.attributes[DDTags.errorType])
        XCTAssertNotNil(spanData.attributes[DDTags.errorMessage])
        XCTAssertNil(spanData.attributes[DDTags.errorStack])
    }

    func testWhenTestCaseDidFinishIsCalledAndTheTestIsABenchmark_benchmarkTagsAreAdded() async {
        let group = DDXCTestRetryGroup(for: self, observer: testObserver)
        testObserver.testBundleWillStart(Bundle.main)
        testObserver.testSuiteWillStart(theSuite)
        testObserver.testRetryGroupWillStart(group)

        let spanData = group.context.suite.withActiveTest(named: self.testId.test) { test in
            let originalRun = self.testRun
            let mockRun = MockXCTestCaseRetryRun(ddTest: test, group: group, xcTest: self)
            self.setValue(mockRun, forKey: "testRun")

            testObserver.testCaseWillStart(self)

            let testSpan = OpenTelemetry.instance.contextProvider.activeSpan as! SpanSdk
            let perfMetric = XCTPerformanceMetric.wallClockTime
            self.setValue([perfMetric], forKey: "_activePerformanceMetricIDs")
            self.setValue([perfMetric: ["measurements": [1, 2, 3, 4, 5]]], forKey: "_perfMetricsForID")

            testObserver.testCaseDidFinish(self)
            let data = testSpan.toSpanData()

            self.setValue(nil, forKey: "_activePerformanceMetricIDs")
            self.setValue(nil, forKey: "_perfMetricsForID")
            self.setValue(originalRun, forKey: "testRun")
            return data
        }

        testObserver.testRetryGroupDidFinish(group)
        testObserver.testSuiteDidFinish(theSuite)
        testObserver.testBundleDidFinish(Bundle.main)
        await destroyObserver()

        XCTAssertEqual(spanData.attributes[DDTestTags.testType]?.description, DDTagValues.typeBenchmark)

        let measure = DDBenchmarkTags.benchmark + "." + DDBenchmarkMeasuresTags.duration + "."
        XCTAssertEqual(spanData.attributes[measure + DDBenchmarkTags.benchmarkMean]?.description, "3000000000.0")
        XCTAssertEqual(spanData.attributes[measure + DDBenchmarkTags.statisticsN]?.description, "5.0")
        XCTAssertEqual(spanData.attributes[measure + DDBenchmarkTags.statisticsMin]?.description, "1000000000.0")
        XCTAssertEqual(spanData.attributes[measure + DDBenchmarkTags.statisticsMax]?.description, "5000000000.0")
        XCTAssertEqual(spanData.attributes[measure + DDBenchmarkTags.statisticsMedian]?.description, "3000000000.0")
    }

    func testWhenTestCaseDidRecordIssueIsCalledTwice_twoErrorsAppear() async {
        let group = DDXCTestRetryGroup(for: self, observer: testObserver)
        testObserver.testBundleWillStart(Bundle.main)
        testObserver.testSuiteWillStart(theSuite)
        testObserver.testRetryGroupWillStart(group)

        let spanData = group.context.suite.withActiveTest(named: self.testId.test) { test in
            let originalRun = self.testRun
            let mockRun = MockXCTestCaseRetryRun(ddTest: test, group: group, xcTest: self)
            self.setValue(mockRun, forKey: "testRun")

            testObserver.testCaseWillStart(self)

            let error1Text = "error1"
            let error2Text = "error2"
            let issue1 = XCTIssue(type: .assertionFailure, compactDescription: error1Text,
                                  detailedDescription: nil, sourceCodeContext: XCTSourceCodeContext(),
                                  associatedError: nil, attachments: [])
            mockRun.addFailure(issue1)
            testObserver.testCase(self, didRecord: issue1)

            let issue2 = XCTIssue(type: .assertionFailure, compactDescription: error2Text,
                                  detailedDescription: nil, sourceCodeContext: XCTSourceCodeContext(),
                                  associatedError: nil, attachments: [])
            mockRun.addFailure(issue2)
            testObserver.testCase(self, didRecord: issue2)

            let testSpan = OpenTelemetry.instance.contextProvider.activeSpan as! SpanSdk
            testObserver.testCaseDidFinish(self)
            
            self.setValue(originalRun, forKey: "testRun")
            return testSpan.toSpanData()
        }

        testObserver.testRetryGroupDidFinish(group)
        testObserver.testSuiteDidFinish(theSuite)
        testObserver.testBundleDidFinish(Bundle.main)
        await destroyObserver()

        XCTAssertTrue(spanData.attributes[DDTags.errorMessage]?.description.contains(exactWord: "error1") ?? false)
        XCTAssertTrue(spanData.attributes[DDTags.errorMessage]?.description.contains(exactWord: "error2") ?? false)
    }

    private func destroyObserver() async {
        await self.session.stop()
        testObserver = nil
    }
}

// MARK: - Mock test run

/// A lightweight XCTestRun subclass used in tests.
/// Extends XCTestRun (not XCTestCaseRun) so start()/stop() don't notify XCTestObservationCenter.
private final class MockXCTestCaseRetryRun: XCTestRun, DDXCTestCaseRetryRunType {
    let ddTest: any TestRun
    let group: any DDXCTestRetryGroupType

    private(set) var suppressedFailures: [XCTIssue] = []
    private(set) var skipReason: String? = nil
    private var _failed: Bool = false
    private var _suppressNext: Bool = false

    init(ddTest: any TestRun, group: any DDXCTestRetryGroupType, xcTest: XCTest) {
        self.ddTest = ddTest
        self.group = group
        super.init(test: xcTest)
    }

    var ddHasFailed: Bool { _failed || !suppressedFailures.isEmpty }
    var ddTotalFailureCount: Int { (_failed ? 1 : 0) + suppressedFailures.count }

    /// Call this to simulate a test failure without affecting the running XCTest.
    func addFailure(_ issue: XCTIssue) {
        if _suppressNext {
            suppressedFailures.append(issue)
            _suppressNext = false
        } else {
            _failed = true
        }
    }

    func suppressFailure() { _suppressNext = true }

    func recordSuppressedFailures() {
        if !suppressedFailures.isEmpty { _failed = true }
        suppressedFailures = []
    }

    func recordSuppressedFailuresAsExpected(reason: String) {
        suppressedFailures = []
    }
}
