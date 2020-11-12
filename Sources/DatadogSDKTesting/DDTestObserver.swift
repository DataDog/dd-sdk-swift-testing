/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import SigmaSwiftStatistics

@_implementationOnly import XCTest

internal class DDTestObserver: NSObject, XCTestObservation {
    var tracer: DDTracer

    let testNameRegex = try? NSRegularExpression(pattern: "([\\w]+) ([\\w]+)", options: .caseInsensitive)
    let supportsSkipping = NSClassFromString("XCTSkippedTestContext") != nil
    var currentBundleName = ""
    let isUITestRunner = Bundle.main.bundleIdentifier?.hasSuffix("xctrunner") ?? false

    init(tracer: DDTracer) {
        if isUITestRunner {
            XCUIApplication.swizzleMethods
        }
        self.tracer = tracer
        super.init()
    }

    func startObserving() {
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        currentBundleName = testBundle.bundleURL.deletingPathExtension().lastPathComponent
        DDCrashes.install()
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        /// We need to wait for all the traces to be written to the backend before exiting
        tracer.flush()
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        guard let namematch = testNameRegex?.firstMatch(in: testCase.name, range: NSRange(location: 0, length: testCase.name.count)),
            let suiteRange = Range(namematch.range(at: 1), in: testCase.name),
            let nameRange = Range(namematch.range(at: 2), in: testCase.name) else {
            return
        }
        let testSuite = String(testCase.name[suiteRange])
        let testName = String(testCase.name[nameRange])

        let attributes: [String: String] = [
            DDTestingTags.type: DDTestingTags.typeTest,
            DDTestingTags.testName: testName,
            DDTestingTags.testSuite: testSuite,
            DDTestingTags.testFramework: "XCTest",
            DDTestingTags.testBundle: currentBundleName,
            DDTestingTags.testType: DDTestingTags.typeTest
        ]

        let testSpan = tracer.startSpan(name: testCase.name, attributes: attributes)
        tracer.env.addTagsToSpan(span: testSpan)

        let simpleSpan = SimpleSpanData(spanData: testSpan.toSpanData())
        DDCrashes.setCustomData(customData: SimpleSpanSerializer.serializeSpan(simpleSpan: simpleSpan))
        tracer.activeTestSpan = testSpan
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        guard let activeTest = tracer.activeTestSpan else {
            return
        }
        var status: String
        if supportsSkipping, testCase.testRun?.hasBeenSkipped == true {
            status = DDTestingTags.statusSkip
        } else if testCase.testRun?.hasSucceeded ?? false {
            status = DDTestingTags.statusPass
        } else {
            status = DDTestingTags.statusFail
            activeTest.status = .internalError
        }

        activeTest.setAttribute(key: DDTestingTags.testStatus, value: status)
        addBenchmarkTagsIfNeeded(testCase: testCase, activeTest: activeTest)
        /// Need to wait for stderr to be written, stdout is synchronous
        DDTestMonitor.instance?.stderrCapturer.synchronize()
        activeTest.end()
        tracer.activeTestSpan = nil
    }

    func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {
        guard let activeTest = tracer.activeTestSpan else {
            return
        }
        activeTest.setAttribute(key: DDTags.errorType, value: AttributeValue.string(description))
        activeTest.setAttribute(key: DDTags.errorMessage, value: AttributeValue.string("test_failure: \(filePath ?? ""):\(lineNumber)"))
        let fullDescription = "\(description):\n\(filePath ?? ""):\(lineNumber)"
        activeTest.setAttribute(key: DDTags.errorStack, value: AttributeValue.string(fullDescription))
    }

    private func addBenchmarkTagsIfNeeded(testCase: XCTestCase, activeTest: Span) {
        guard let metricsForId = testCase.value(forKey: "_perfMetricsForID") as? [XCTPerformanceMetric: AnyObject],
            let metric = metricsForId.first(where: {
                let measurements = $0.value.value(forKey: "measurements") as? [Double]
                return (measurements?.count ?? 0) > 0
            }) else {
            return
        }

        guard let measurements = metric.value.value(forKey: "measurements") as? [Double] else {
            return
        }

        activeTest.setAttribute(key: DDTestingTags.testType, value: DDTestingTags.typeBenchmark)
        let values = measurements.map { $0 * 1_000_000_000 } // Convert to nanoseconds
        activeTest.setAttribute(key: DDBenchmarkingTags.statisticsN, value: values.count)
        if let average = Sigma.average(values) {
            activeTest.setAttribute(key: DDBenchmarkingTags.durationMean, value: average)
        }
        if let max = Sigma.max(values) {
            activeTest.setAttribute(key: DDBenchmarkingTags.statisticsMax, value: max)
        }
        if let min = Sigma.min(values) {
            activeTest.setAttribute(key: DDBenchmarkingTags.statisticsMin, value: min)
        }
        if let mean = Sigma.average(values) {
            activeTest.setAttribute(key: DDBenchmarkingTags.statisticsMean, value: mean)
        }
        if let median = Sigma.median(values) {
            activeTest.setAttribute(key: DDBenchmarkingTags.statisticsMedian, value: median)
        }
        if let stdDev = Sigma.standardDeviationSample(values) {
            activeTest.setAttribute(key: DDBenchmarkingTags.statisticsStdDev, value: stdDev)
        }
        if let stdErr = Sigma.standardErrorOfTheMean(values) {
            activeTest.setAttribute(key: DDBenchmarkingTags.statisticsStdErr, value: stdErr)
        }
        if let kurtosis = Sigma.kurtosisA(values) {
            activeTest.setAttribute(key: DDBenchmarkingTags.statisticsKurtosis, value: kurtosis)
        }
        if let skewness = Sigma.skewnessA(values) {
            activeTest.setAttribute(key: DDBenchmarkingTags.statisticsSkewness, value: skewness)
        }
        if let percentile99 = Sigma.percentile(values, percentile: 0.99) {
            activeTest.setAttribute(key: DDBenchmarkingTags.statisticsP99, value: percentile99)
        }
        if let percentile95 = Sigma.percentile(values, percentile: 0.95) {
            activeTest.setAttribute(key: DDBenchmarkingTags.statisticsP99, value: percentile95)
        }
        if let percentile90 = Sigma.percentile(values, percentile: 0.90) {
            activeTest.setAttribute(key: DDBenchmarkingTags.statisticsP99, value: percentile90)
        }
    }
}
