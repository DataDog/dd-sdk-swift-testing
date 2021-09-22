/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
@_implementationOnly import OpenTelemetryApi
@_implementationOnly import OpenTelemetrySdk
@_implementationOnly import SigmaSwiftStatistics
@_implementationOnly import XCTest

class DDTestObserver: NSObject, XCTestObservation {
    static let testNameRegex = try! NSRegularExpression(pattern: "([\\w]+) ([\\w]+)", options: .caseInsensitive)
    static let supportsSkipping = NSClassFromString("XCTSkippedTestContext") != nil
    static let tracerVersion = (Bundle(for: DDTestObserver.self).infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"

    weak var ddTest: DDTest!
    init(ddTest: DDTest) {
        self.ddTest = ddTest
        XCUIApplication.swizzleMethods
        super.init()
    }

    func startObserving() {
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        let bundleName = testBundle.bundleURL.deletingPathExtension().lastPathComponent
        ddTest.bundleStart(name: bundleName)
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        /// We need to wait for all the traces to be written to the backend before exiting
        ddTest.bundleEnd()
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        guard let namematch = DDTestObserver.testNameRegex.firstMatch(in: testCase.name, range: NSRange(location: 0, length: testCase.name.count)),
              let suiteRange = Range(namematch.range(at: 1), in: testCase.name),
              let nameRange = Range(namematch.range(at: 2), in: testCase.name)
        else {
            return
        }
        let testSuite = String(testCase.name[suiteRange])
        let testName = String(testCase.name[nameRange])

        ddTest.start(name: testName, testSuite: testSuite)
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        addBenchmarkTagsIfNeeded(testCase: testCase)

        if DDTestObserver.supportsSkipping, testCase.testRun?.hasBeenSkipped == true {
            ddTest.end(status: .skip)
        } else if testCase.testRun?.hasSucceeded ?? false {
            ddTest.end(status: .pass)
        } else {
            ddTest.end(status: .fail)
        }
    }

    #if swift(>=5.3)
    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        ddTest.setErrorInfo(type: issue.compactDescription, message: issue.description, callStack: issue.detailedDescription)
    }
    #else
    func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {
        ddTest.testSetErrorInfo(type: description, message: "test_failure: \(filePath ?? ""):\(lineNumber)", callStack: nil)
    }
    #endif

    private func addBenchmarkTagsIfNeeded(testCase: XCTestCase) {
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
        ddTest.testSetBenchmarkInfo(measureName: "", measureUnit: "", values: values)
    }
}
