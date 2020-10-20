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
    var activeTestSpan: Span?

    init(tracer: DDTracer) {
        self.tracer = tracer
        super.init()
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
            DDTestingTags.testTraits: currentBundleName,
            DDTestingTags.testType: DDTestingTags.typeTest
        ]

        let testSpan = tracer.startSpan(name: testCase.name, attributes: attributes)
        tracer.env.addTagsToSpan(span: testSpan)

        let simpleSpan = SimpleSpanData(spanData: testSpan.toSpanData())
        DDCrashes.setCustomData(customData: SimpleSpanSerializer.serializeSpan(simpleSpan: simpleSpan))
        activeTestSpan = testSpan
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        guard let activeTest = activeTestSpan else {
            return
        }
        var status: String
        if supportsSkipping && testCase.testRun?.hasBeenSkipped == true {
            status = DDTestingTags.statusSkip
        } else if testCase.testRun?.hasSucceeded ?? false {
            status = DDTestingTags.statusPass
        } else {
            status = DDTestingTags.statusFail
            activeTestSpan?.setAttribute(key: DDTags.error, value: true)
        }

        activeTest.setAttribute(key: DDTestingTags.testStatus, value: status)
        addBenchmarkTagsIfNeeded(testCase: testCase, activeTest: activeTest)
        activeTest.end()
        activeTestSpan = nil
    }

    func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {
        self.activeTestSpan?.setAttribute(key: DDTags.errorType, value: AttributeValue.string("test_failure: \(filePath ?? ""):\(lineNumber)"))
        self.activeTestSpan?.setAttribute(key: DDTags.errorMessage, value: AttributeValue.string(description))
        let fullDescription = "\(description):\n\(filePath ?? ""):\(lineNumber)"
        self.activeTestSpan?.setAttribute(key: DDTags.errorStack, value: AttributeValue.string(fullDescription))
    }

    private func addBenchmarkTagsIfNeeded(testCase: XCTestCase, activeTest: Span) {
        guard let activeMetrics = testCase.value(forKey: "_activePerformanceMetricIDs") as? [XCTPerformanceMetric],
              let metricsForId = testCase.value(forKey: "_perfMetricsForID") as? [XCTPerformanceMetric: AnyObject] else {
            return
        }
        activeTest.setAttribute(key: DDTestingTags.testType, value: DDTestingTags.typeBenchmark)

        for metric in activeMetrics {
            guard let measurements = metricsForId[metric]?.value(forKey: "measurements") as? [Double]  else {
                return
            }
            let values = measurements.map{ $0 * 1_000_000_000 } // Convert to nanoseconds 
            switch metric {
                case XCTPerformanceMetric.wallClockTime:
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
                        activeTest.setAttribute(key: DDBenchmarkingTags.statisticsP99, value: percentile99 )
                    }
                    if let percentile95 = Sigma.percentile(values, percentile: 0.95) {
                        activeTest.setAttribute(key: DDBenchmarkingTags.statisticsP99, value: percentile95 )
                    }
                    if let percentile90 = Sigma.percentile(values, percentile: 0.90) {
                        activeTest.setAttribute(key: DDBenchmarkingTags.statisticsP99, value: percentile90 )
                    }
                default:
                    print("Unknown metric")
            }
        }
    }
}

