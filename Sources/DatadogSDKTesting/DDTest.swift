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

@objc public enum DDTestStatus: Int {
    case pass
    case fail
    case skip
}

public class DDTest: NSObject {
    static var instance: DDTest?

    var testObserver: DDTestObserver?

    var tracer: DDTracer

    static let testNameRegex = try! NSRegularExpression(pattern: "([\\w]+) ([\\w]+)", options: .caseInsensitive)
    static let supportsSkipping = NSClassFromString("XCTSkippedTestContext") != nil
    var currentBundleName = ""
    var currentBundleFunctionInfo = FunctionMap()
    var currentTestExecutionOrder = 0
    var initialProcessId = Int(ProcessInfo.processInfo.processIdentifier)
    var codeOwners: CodeOwners?

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

    internal init(tracer: DDTracer) {
        self.tracer = tracer
        super.init()
        testObserver = DDTestObserver(ddTest: self)
    }

    func bundleStart(name: String) {
        currentBundleName = name
        #if !os(tvOS) && (targetEnvironment(simulator) || os(macOS))
        DDSymbolicator.createDSYMFileIfNeeded(forImageName: name)
        currentBundleFunctionInfo = FileLocator.testFunctionsInModule(name)
        #endif
        if let workspacePath = tracer.env.workspacePath {
            codeOwners = CodeOwners(workspacePath: URL(fileURLWithPath: workspacePath))
        }

        if !tracer.env.disableCrashHandler {
            DDCrashes.install()
        }
    }

    func bundleEnd() {
        /// We need to wait for all the traces to be written to the backend before exiting
        tracer.flush()
    }

    func start(name: String, testSuite: String) {
        currentTestExecutionOrder = currentTestExecutionOrder + 1

        let attributes: [String: String] = [
            DDGenericTags.type: DDTagValues.typeTest,
            DDGenericTags.resourceName: "\(currentBundleName).\(testSuite).\(name)",
            DDTestTags.testName: name,
            DDTestTags.testSuite: testSuite,
            DDTestTags.testFramework: "XCTest",
            DDTestTags.testBundle: currentBundleName,
            DDTestTags.testType: DDTagValues.typeTest,
            DDTestTags.testExecutionOrder: "\(currentTestExecutionOrder)",
            DDTestTags.testExecutionProcessId: "\(initialProcessId)",
            DDOSTags.osPlatform: tracer.env.osName,
            DDOSTags.osArchitecture: tracer.env.osArchitecture,
            DDOSTags.osVersion: tracer.env.osVersion,
            DDDeviceTags.deviceName: tracer.env.deviceName,
            DDDeviceTags.deviceModel: tracer.env.deviceModel,
            DDRuntimeTags.runtimeName: "Xcode",
            DDRuntimeTags.runtimeVersion: tracer.env.runtimeVersion,
            DDTracerTags.tracerLanguage: "swift",
            DDTracerTags.tracerVersion: DDTestObserver.tracerVersion
        ]

        let testSpan = tracer.startSpan(name: "\(testSuite).\(name)()", attributes: attributes)

        // Is not a UITest until a XCUIApplication is launched
        testSpan.setAttribute(key: DDTestTags.testIsUITest, value: false)

        if !tracer.env.disableDDSDKIOSIntegration {
            tracer.addPropagationsHeadersToEnvironment()
        }

        let functionName = testSuite + "." + name
        if let functionInfo = currentBundleFunctionInfo[functionName] {
            var filePath = functionInfo.file
            if let workspacePath = tracer.env.workspacePath,
               let workspaceRange = filePath.range(of: workspacePath + "/")
            {
                filePath.removeSubrange(workspaceRange)
            }
            testSpan.setAttribute(key: DDTestTags.testSourceFile, value: filePath)
            testSpan.setAttribute(key: DDTestTags.testSourceStartLine, value: functionInfo.startLine)
            testSpan.setAttribute(key: DDTestTags.testSourceEndLine, value: functionInfo.endLine)
            if let owners = codeOwners?.ownersForPath(filePath) {
                testSpan.setAttribute(key: DDTestTags.testCodeowners, value: owners)
            }
        }

        tracer.env.addTagsToSpan(span: testSpan)

        if let testSpan = testSpan as? RecordEventsReadableSpan {
            let simpleSpan = SimpleSpanData(spanData: testSpan.toSpanData())
            DDCrashes.setCustomData(customData: SimpleSpanSerializer.serializeSpan(simpleSpan: simpleSpan))
        }
        currentTestSpan = testSpan
    }

    func setAttribute(key: String, value: Any) {
        guard let activeTest = currentTestSpan else {
            return
        }
        activeTest.setAttribute(key: key, value: AttributeValue(value))
    }

    func setErrorInfo(type: String, message: String, callStack: String?) {
        guard let activeTest = currentTestSpan else {
            return
        }

        activeTest.setAttribute(key: DDTags.errorType, value: AttributeValue.string(type))
        activeTest.setAttribute(key: DDTags.errorMessage, value: AttributeValue.string(message))
        if let callStack = callStack {
            activeTest.setAttribute(key: DDTags.errorStack, value: AttributeValue.string(callStack))
        }
    }

    func end(status: DDTestStatus) {
        guard let activeTest = currentTestSpan else {
            return
        }

        let testStatus: String
        switch status {
            case .pass:
                testStatus = DDTagValues.statusPass
                activeTest.status = .ok
            case .fail:
                testStatus = DDTagValues.statusFail
                activeTest.status = .error(description: "Test failed")
            case .skip:
                testStatus = DDTagValues.statusSkip
                activeTest.status = .ok
        }

        activeTest.setAttribute(key: DDTestTags.testStatus, value: testStatus)
        activeTest.end()
        tracer.backgroundWorkQueue.sync {}
        currentTestSpan = nil
        DDTestMonitor.instance?.networkInstrumentation?.endAndCleanAliveSpans()
    }

    func testSetBenchmarkInfo(measureName: String, measureUnit: String, values: [Double]) {
        guard let activeTest = currentTestSpan else {
            return
        }
        activeTest.setAttribute(key: DDTestTags.testType, value: DDTagValues.typeBenchmark)
        activeTest.setAttribute(key: DDBenchmarkTags.benchmarkRuns, value: values.count)
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
            activeTest.setAttribute(key: DDBenchmarkTags.statisticsP95, value: percentile95)
        }
        if let percentile90 = Sigma.percentile(values, percentile: 0.90) {
            activeTest.setAttribute(key: DDBenchmarkTags.statisticsP90, value: percentile90)
        }
    }
}

public extension DDTest {
    // Public interface for DDTest

    @objc static func bundleStart(name: String) {
        DDTest.instance?.bundleStart(name: name)
    }

    @objc static func bundleEnd() {
        DDTest.instance?.bundleEnd()
    }

    @objc static func start(name: String, testSuite: String) {
        DDTest.instance?.start(name: name, testSuite: testSuite)
    }

    @objc static func setAttribute(key: String, value: Any) {
        DDTest.instance?.setAttribute(key: key, value: value)
    }

    @objc static func setErrorInfo(type: String, message: String, callStack: String?) {
        DDTest.instance?.setErrorInfo(type: type, message: message, callStack: callStack)
    }

    @objc static func end(status: DDTestStatus) {
        DDTest.instance?.end(status: status)
    }

    @objc static func setBenchmarkInfo(measureName: String, measureUnit: String, values: [Double]) {
        DDTest.instance?.testSetBenchmarkInfo(measureName: measureName, measureUnit: measureUnit, values: values)
    }
}
