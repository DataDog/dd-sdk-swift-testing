/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
@_implementationOnly import XCTest

class DDTestObserver: NSObject, XCTestObservation {
    static let testNameRegex = try! NSRegularExpression(pattern: "([\\w]+) ([\\w]+)", options: .caseInsensitive)
    static let supportsSkipping = NSClassFromString("XCTSkippedTestContext") != nil
    static let tracerVersion = (Bundle(for: DDTestObserver.self).infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"

    var session: DDTestSession?
    var suite: DDTestSuite?
    var test: DDTest?

    override init() {
        XCUIApplication.swizzleMethods
        super.init()
    }

    func startObserving() {
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        let bundleName = testBundle.bundleURL.deletingPathExtension().lastPathComponent
        session = DDTestSession(bundleName: bundleName)
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        /// We need to wait for all the traces to be written to the backend before exiting
        session?.end()
    }

    func testSuiteWillStart(_ testSuite: XCTestSuite) {
        suite = session?.suiteStart(name: testSuite.name)
    }

    func testSuiteDidFinish(_ testSuite: XCTestSuite) {
        if let suite = suite {
            session?.suiteEnd(suite: suite)
        }
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        guard let session = session,
              let suite = suite,
              let namematch = DDTestObserver.testNameRegex.firstMatch(in: testCase.name, range: NSRange(location: 0, length: testCase.name.count)),
              let nameRange = Range(namematch.range(at: 2), in: testCase.name)
        else {
            return
        }
        let testName = String(testCase.name[nameRange])

        test = session.testStart(name: testName, suite: suite)
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        guard let session = session,
              let test = test
        else {
            return
        }
        addBenchmarkTagsIfNeeded(testCase: testCase, test: test)

        if DDTestObserver.supportsSkipping, testCase.testRun?.hasBeenSkipped == true {
            session.testEnd(test: test, status: .skip)
        } else if testCase.testRun?.hasSucceeded ?? false {
            session.testEnd(test: test, status: .pass)
        } else {
            session.testEnd(test: test, status: .fail)
        }
    }

    #if swift(>=5.3)
    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        guard let session = session,
              let test = test
        else {
            return
        }
        session.testSetErrorInfo(test: test, type: issue.compactDescription, message: issue.description, callstack: issue.detailedDescription)
    }
    #else
    func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {
        guard let session = session,
              let test = test
        else {
            return
        }
        session.testSetErrorInfo(test: test, type: description, message: "test_failure: \(filePath ?? ""):\(lineNumber)", callstack: nil)
    }
    #endif

    private func addBenchmarkTagsIfNeeded(testCase: XCTestCase, test: DDTest) {
        guard let metricsForId = testCase.value(forKey: "_perfMetricsForID") as? [XCTPerformanceMetric: AnyObject],
              let metric = metricsForId.first(where: {
                  let measurements = $0.value.value(forKey: "measurements") as? [Double]
                  return (measurements?.count ?? 0) > 0
              })
        else {
            return
        }

        guard let measurements = metric.value.value(forKey: "measurements") as? [Double] else {
            return
        }

        let values = measurements.map { $0 * 1_000_000_000 } // Convert to nanoseconds
        test.setBenchmarkInfo(measureName: "", measureUnit: "", values: values)
    }
}
