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
    var currentBundleFunctionInfo = FunctionMap()

    var rLock = NSRecursiveLock()
    private var privateCurrentTestSpan: Span?
    var currentTestSpan: Span? {
        get {
            rLock.lock()
            defer { rLock.unlock() }
            return privateCurrentTestSpan
        }
        set {
            rLock.lock()
            defer { rLock.unlock() }
            privateCurrentTestSpan = newValue
        }
    }

    init(tracer: DDTracer) {
        XCUIApplication.swizzleMethods
        self.tracer = tracer
        super.init()
    }

    func startObserving() {
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        #if !os(tvOS) && ( targetEnvironment(simulator) || os(macOS) )
        currentBundleName = testBundle.bundleURL.deletingPathExtension().lastPathComponent
        DDSymbolicator.createDSYMFileIfNeeded(forImageName: currentBundleName)

        let currentTargetName = Bundle.main.bundleURL.deletingPathExtension().lastPathComponent
        DDSymbolicator.createDSYMFileIfNeeded(forImageName: currentTargetName)

        currentBundleFunctionInfo = FileLocator.functionsInModule(currentBundleName)

        #endif
        if !tracer.env.disableCrashHandler {
            DDCrashes.install()
        }
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        /// We need to wait for all the traces to be written to the backend before exiting
        tracer.flush()
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        guard let namematch = testNameRegex?.firstMatch(in: testCase.name, range: NSRange(location: 0, length: testCase.name.count)),
              let suiteRange = Range(namematch.range(at: 1), in: testCase.name),
              let nameRange = Range(namematch.range(at: 2), in: testCase.name)
        else {
            return
        }
        let testSuite = String(testCase.name[suiteRange])
        let testName = String(testCase.name[nameRange])

        let attributes: [String: String] = [
            DDGenericTags.language: "swift",
            DDGenericTags.type: DDTestTags.typeTest,
            DDGenericTags.resourceName: "\(currentBundleName).\(testSuite).\(testName)",
            DDTestTags.testName: testName,
            DDTestTags.testSuite: testSuite,
            DDTestTags.testFramework: "XCTest",
            DDTestTags.testBundle: currentBundleName,
            DDTestTags.testType: DDTestTags.typeTest,
            DDOSTags.osPlatform: tracer.env.osName,
            DDOSTags.osArchitecture: tracer.env.osArchitecture,
            DDOSTags.osVersion: tracer.env.osVersion,
            DDDeviceTags.deviceName: tracer.env.deviceName,
            DDDeviceTags.deviceModel: tracer.env.deviceModel,
            DDRuntimeTags.runtimeName: "Xcode",
            DDRuntimeTags.runtimeVersion: tracer.env.runtimeVersion
        ]

        let testSpan = tracer.startSpan(name: testCase.name, attributes: attributes)
        if !tracer.env.disableDDSDKIOSIntegration {
            tracer.addPropagationsHeadersToEnvironment()
        }

        let functionName = testSuite + "." + testName
        if let functionInfo = currentBundleFunctionInfo[functionName] {
            var filePath = functionInfo.file
            if let srcRoot = tracer.env.sourceRoot,
               let rootRange = filePath.range(of: srcRoot + "/")
            {
                filePath.removeSubrange(rootRange)
            }
            testSpan.setAttribute(key: DDTestTags.testSourceFile, value: filePath)
            testSpan.setAttribute(key: DDTestTags.testSourceStartLine, value: functionInfo.startLine)
            testSpan.setAttribute(key: DDTestTags.testSourceEndLine, value: functionInfo.endLine)
        }

        tracer.env.addTagsToSpan(span: testSpan)

        if let testSpan = testSpan as? RecordEventsReadableSpan {
            let simpleSpan = SimpleSpanData(spanData: testSpan.toSpanData())
            DDCrashes.setCustomData(customData: SimpleSpanSerializer.serializeSpan(simpleSpan: simpleSpan))
        }
        currentTestSpan = testSpan
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        guard let activeTest = currentTestSpan else {
            return
        }
        var status: String
        if supportsSkipping, testCase.testRun?.hasBeenSkipped == true {
            status = DDTestTags.statusSkip
            activeTest.status = .ok
        } else if testCase.testRun?.hasSucceeded ?? false {
            status = DDTestTags.statusPass
            activeTest.status = .ok
        } else {
            status = DDTestTags.statusFail
            activeTest.status = .error(description: "Test failed")
        }

        activeTest.setAttribute(key: DDTestTags.testStatus, value: status)
        addBenchmarkTagsIfNeeded(testCase: testCase, activeTest: activeTest)
        activeTest.end()
        currentTestSpan = nil
        DDTestMonitor.instance?.networkInstrumentation?.endAndCleanAliveSpans()
    }

    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        guard let activeTest = currentTestSpan else {
            return
        }
        activeTest.setAttribute(key: DDTags.errorType, value: AttributeValue.string(issue.compactDescription))
        activeTest.setAttribute(key: DDTags.errorMessage, value: AttributeValue.string(issue.description))
        if let detailedDescription = issue.detailedDescription {
            activeTest.setAttribute(key: DDTags.errorStack, value: AttributeValue.string(detailedDescription))
        }
    }

    private func addBenchmarkTagsIfNeeded(testCase: XCTestCase, activeTest: Span) {
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

        activeTest.setAttribute(key: DDTestTags.testType, value: DDTestTags.typeBenchmark)
        let values = measurements.map { $0 * 1_000_000_000 } // Convert to nanoseconds
        activeTest.setAttribute(key: DDBenchmarkTags.statisticsN, value: values.count)
        if let average = Sigma.average(values) {
            activeTest.setAttribute(key: DDBenchmarkTags.durationMean, value: average)
        }
        if let max = Sigma.max(values) {
            activeTest.setAttribute(key: DDBenchmarkTags.statisticsMax, value: max)
        }
        if let min = Sigma.min(values) {
            activeTest.setAttribute(key: DDBenchmarkTags.statisticsMin, value: min)
        }
        if let mean = Sigma.average(values) {
            activeTest.setAttribute(key: DDBenchmarkTags.statisticsMean, value: mean)
        }
        if let median = Sigma.median(values) {
            activeTest.setAttribute(key: DDBenchmarkTags.statisticsMedian, value: median)
        }
        if let stdDev = Sigma.standardDeviationSample(values) {
            activeTest.setAttribute(key: DDBenchmarkTags.statisticsStdDev, value: stdDev)
        }
        if let stdErr = Sigma.standardErrorOfTheMean(values) {
            activeTest.setAttribute(key: DDBenchmarkTags.statisticsStdErr, value: stdErr)
        }
        if let kurtosis = Sigma.kurtosisA(values) {
            activeTest.setAttribute(key: DDBenchmarkTags.statisticsKurtosis, value: kurtosis)
        }
        if let skewness = Sigma.skewnessA(values) {
            activeTest.setAttribute(key: DDBenchmarkTags.statisticsSkewness, value: skewness)
        }
        if let percentile99 = Sigma.percentile(values, percentile: 0.99) {
            activeTest.setAttribute(key: DDBenchmarkTags.statisticsP99, value: percentile99)
        }
        if let percentile95 = Sigma.percentile(values, percentile: 0.95) {
            activeTest.setAttribute(key: DDBenchmarkTags.statisticsP99, value: percentile95)
        }
        if let percentile90 = Sigma.percentile(values, percentile: 0.90) {
            activeTest.setAttribute(key: DDBenchmarkTags.statisticsP99, value: percentile90)
        }
    }
}
