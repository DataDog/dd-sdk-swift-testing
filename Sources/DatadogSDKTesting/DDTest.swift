/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import OpenTelemetryApi
internal import OpenTelemetrySdk
internal import SigmaSwiftStatistics

@objc(DDTest)
public final class Test: NSObject {
    var currentTestExecutionOrder: UInt
    var initialProcessId = Int(ProcessInfo.processInfo.processIdentifier)

    let name: String
    let startTime: Date
    var span: Span
    var duration: UInt64

    let suite: TestSuite

    private var errorInfo: ErrorInfo?

    init(name: String, suite: TestSuite, startTime: Date? = nil) {
        let testStartTime = startTime ?? DDTestMonitor.clock.now
        self.name = name
        self.suite = suite
        self.duration = 0

        currentTestExecutionOrder = suite.session.nextTestIndex()

        let attributes: [String: String] = [
            DDGenericTags.type: DDTagValues.typeTest,
            DDGenericTags.resource: "\(suite.name).\(name)",
            DDTestTags.testName: name,
            DDTestTags.testSuite: suite.name,
            DDTestTags.testModule: suite.module.name,
            DDTestTags.testFramework: suite.session.testFramework,
            DDTestTags.testType: DDTagValues.typeTest,
            DDTestTags.testIsUITest: "false",
            DDTestSuiteVisibilityTags.testSessionId: suite.session.id.hexString,
            DDTestSuiteVisibilityTags.testModuleId: suite.module.id.hexString,
            DDTestSuiteVisibilityTags.testSuiteId: suite.id.hexString,
            DDUISettingsTags.uiSettingsSuiteLocalization: suite.localization,
            DDUISettingsTags.uiSettingsModuleLocalization: suite.module.localization,
        ]
        
        self.startTime = testStartTime

        span = DDTestMonitor.tracer.startSpan(name: "\(suite.session.testFramework).test",
                                              attributes: attributes,
                                              startTime: testStartTime)
        span.setAttribute(key: DDTestTags.testExecutionOrder, value: Int(currentTestExecutionOrder))
        span.setAttribute(key: DDTestTags.testExecutionProcessId, value: initialProcessId)

        super.init()
        DDTestMonitor.instance?.currentTest = self

        DDTestMonitor.tracer.addPropagationsHeadersToEnvironment()
        
        // Move to the global when we will support global metrics
        for metric in DDTestMonitor.env.baseMetrics {
            span.setAttribute(key: metric.key, value: metric.value)
        }

        let functionName = suite.name + "." + name
        if let functionInfo = DDTestMonitor.instance?.bundleFunctionInfo[functionName] {
            var filePath = functionInfo.file
            if let workspacePath = DDTestMonitor.env.workspacePath,
               let workspaceRange = filePath.range(of: workspacePath + "/")
            {
                filePath.removeSubrange(workspaceRange)
            }
            span.setAttribute(key: DDTestTags.testSourceFile, value: filePath)
            span.setAttribute(key: DDTestTags.testSourceStartLine, value: functionInfo.startLine)
            span.setAttribute(key: DDTestTags.testSourceEndLine, value: functionInfo.endLine)
            if let owners = DDTestMonitor.instance?.codeOwners?.ownersForPath(filePath) {
                span.setAttribute(key: DDTestTags.testCodeowners, value: owners)
            }
        }
        
        if let testSpan = span as? RecordEventsReadableSpan {
            let simpleSpan = SimpleSpanData(spanData: testSpan.toSpanData(), moduleStartTime: module.startTime, suiteStartTime: suite.startTime)
            DDCrashes.setCurrent(spanData: simpleSpan)
        }
    }

    func setIsUITest(_ value: Bool) {
        self.span.setAttribute(key: DDTestTags.testIsUITest, value: value ? "true" : "false")

        // Set default UI values if nor previously set and update crash customData
        if let testSpan = span as? RecordEventsReadableSpan {
            let spanData = testSpan.toSpanData()
            if spanData.attributes[DDUISettingsTags.uiSettingsAppearance] == nil {
                setTag(key: DDUISettingsTags.uiSettingsAppearance, value: PlatformUtils.getAppearance())
            }
#if os(iOS)
            if spanData.attributes[DDUISettingsTags.uiSettingsOrientation] == nil {
                setTag(key: DDUISettingsTags.uiSettingsOrientation, value: PlatformUtils.getOrientation())
            }
#endif
            let simpleSpan = SimpleSpanData(spanData: testSpan.toSpanData(), sessionStertTine: session.startTime, moduleStartTime: module.startTime, suiteStartTime: suite.startTime)
            DDCrashes.setCurrent(spanData: simpleSpan)
        }
    }

    /// Adds a extra tag or attribute to the test, any number of tags can be reported
    /// - Parameters:
    ///   - key: The name of the tag, if a tag exists with the name it will be
    ///     replaced with the new value
    ///   - value: The value of the tag, can be a number or a string.
    @objc public func setTag(key: String, value: Any) {
        span.setAttribute(key: key, value: AttributeValue(value))
    }

    /// Adds error information to the test, several errors can be added. Only first will set the error type, but all error messages
    /// will be shown in the error messages. If stdout or stderr instrumentation are enabled, errors will also be logged.
    /// - Parameters:
    ///   - type: The type of error to be reported
    ///   - message: The message associated with the error
    ///   - callstack: (Optional) The callstack associated with the error
    @objc public func setErrorInfo(type: String, message: String, callstack: String? = nil) {
        if errorInfo == nil {
            errorInfo = ErrorInfo(type: type, message: message, callstack: callstack)
        } else {
            errorInfo?.addExtraError(message: message)
        }
        DDTestMonitor.tracer.logError(string: "\(type): \(message)")
    }

    private func setErrorInformation() {
        guard let errorInfo = errorInfo else { return }
        span.setAttribute(key: DDTags.errorType, value: AttributeValue.string(errorInfo.type))
        span.setAttribute(key: DDTags.errorMessage, value: AttributeValue.string(errorInfo.message))
        if let callstack = errorInfo.callstack {
            span.setAttribute(key: DDTags.errorStack, value: AttributeValue.string(callstack))
        }
    }

    /// Ends the test
    /// - Parameters:
    ///   - status: the status reported for this test
    ///   - endTime: Optional, the time where the test ended
    @objc public func end(status: TestStatus, endTime: Date?) {
        internalEnd(status: status, endTime: endTime)
    }

    /// Ends the test
    /// - Parameters:
    ///   - status: the status reported for this test
    @objc public func end(status: TestStatus) {
        end(status: status, endTime: nil)
    }

    /// Adds benchmark information to the test, it also changes the test to be of type
    /// benchmark
    /// - Parameters:
    ///   - name: Name of the measure benchmarked
    ///   - samples: Array for values sampled for the measure
    ///   - info: (Optional) Extra information about the benchmark
    @objc func addBenchmarkData(name: String, samples: [Double], info: String?) {
        span.setAttribute(key: DDTestTags.testType, value: DDTagValues.typeBenchmark)

        let tag = DDBenchmarkTags.benchmark + "." + name + "."

        if let benchmarkInfo = info {
            span.setAttribute(key: tag + DDBenchmarkTags.benchmarkInfo, value: benchmarkInfo)
        }
        span.setAttribute(key: tag + DDBenchmarkTags.benchmarkRun, value: samples.count)
        span.setAttribute(key: tag + DDBenchmarkTags.statisticsN, value: samples.count)
        if let average = Sigma.average(samples) {
            span.setAttribute(key: tag + DDBenchmarkTags.benchmarkMean, value: average)
        }
        if let max = Sigma.max(samples) {
            span.setAttribute(key: tag + DDBenchmarkTags.statisticsMax, value: max)
        }
        if let min = Sigma.min(samples) {
            span.setAttribute(key: tag + DDBenchmarkTags.statisticsMin, value: min)
        }
        if let mean = Sigma.average(samples) {
            span.setAttribute(key: tag + DDBenchmarkTags.statisticsMean, value: mean)
        }
        if let median = Sigma.median(samples) {
            span.setAttribute(key: tag + DDBenchmarkTags.statisticsMedian, value: median)
        }
        if let stdDev = Sigma.standardDeviationSample(samples) {
            span.setAttribute(key: tag + DDBenchmarkTags.statisticsStdDev, value: stdDev)
        }
        if let stdErr = Sigma.standardErrorOfTheMean(samples) {
            span.setAttribute(key: tag + DDBenchmarkTags.statisticsStdErr, value: stdErr)
        }
        if let kurtosis = Sigma.kurtosisA(samples), kurtosis.isFinite {
            span.setAttribute(key: tag + DDBenchmarkTags.statisticsKurtosis, value: kurtosis)
        }
        if let skewness = Sigma.skewnessA(samples), skewness.isFinite {
            span.setAttribute(key: tag + DDBenchmarkTags.statisticsSkewness, value: skewness)
        }
        if let percentile99 = Sigma.percentile(samples, percentile: 0.99) {
            span.setAttribute(key: tag + DDBenchmarkTags.statisticsP99, value: percentile99)
        }
        if let percentile95 = Sigma.percentile(samples, percentile: 0.95) {
            span.setAttribute(key: tag + DDBenchmarkTags.statisticsP95, value: percentile95)
        }
        if let percentile90 = Sigma.percentile(samples, percentile: 0.90) {
            span.setAttribute(key: tag + DDBenchmarkTags.statisticsP90, value: percentile90)
        }
    }
    
    /// Current active test
    @objc public static var current: Test? { DDTestMonitor.instance?.currentTest }
}

extension Test: TestRun {
    var id: SpanId { span.context.spanId }
    
    var status: TestStatus {
        switch span.status {
        case .unset, .ok: return .pass
        case .error: return .fail
        }
    }
    
    func set(tag name: String, value: SpanAttributeConvertible) {
        setTag(key: name, value: value)
    }
    
    func set(metric name: String, value: Double) {
        setTag(key: name, value: value)
    }
    
    func add(error: TestError) {
        setErrorInfo(type: error.type, message: error.message ?? "", callstack: error.stack)
    }
    
    func add(benchmark name: String, samples: [Double], info: String?) {
        addBenchmarkData(name: name, samples: samples, info: info)
    }
    
    func end(status: TestStatus, time: Date?) {
        end(status: status, endTime: time)
    }
}

extension Test {
    func internalEnd(status: TestStatus, endTime: Date? = nil) {
        let testEndTime = endTime ?? DDTestMonitor.clock.now
        duration = testEndTime.timeIntervalSince(startTime).toNanoseconds
        
        switch status {
        case .pass:
            span.setAttribute(key: DDTestTags.testStatus, value: DDTagValues.statusPass)
            span.status = .ok
        case .fail:
            span.setAttribute(key: DDTestTags.testStatus, value: DDTagValues.statusFail)
            // suite.set(failed: nil)
            setErrorInformation()
            span.status = .error(description: "Test failed")
        case .skip:
            span.setAttribute(key: DDTestTags.testStatus, value: DDTagValues.statusSkip)
            span.status = .ok
        }

        StderrCapture.syncData()
        span.end(time: testEndTime)
        DDTestMonitor.instance?.networkInstrumentation?.endAndCleanAliveSpans()
        DDCrashes.setCurrent(spanData: nil)
        DDTestMonitor.instance?.currentTest = nil
    }
}

private struct ErrorInfo {
    var type: String
    var message: String
    var callstack: String?
    var errorCount = 1

    mutating func addExtraError(message newMessage: String) {
        if errorCount == 1 {
            message.insert("\n", at: message.startIndex)
        }
        message.append("\n" + newMessage)
        errorCount += 1
    }
}
