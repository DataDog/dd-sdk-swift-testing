/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import OpenTelemetryApi
@_implementationOnly import OpenTelemetrySdk
@_implementationOnly import SigmaSwiftStatistics

public class DDTest: NSObject {
    static let testNameRegex = try! NSRegularExpression(pattern: "([\\w]+) ([\\w]+)", options: .caseInsensitive)
    var currentTestExecutionOrder: Int
    var initialProcessId = Int(ProcessInfo.processInfo.processIdentifier)

    let name: String
    let span: Span

//    var module: DDTestModule
    let suite: DDTestSuite

    private var isUITest: Bool

    private var errorInfo: ErrorInfo?
    
    private(set) var status: DDTestStatus.ITR
    private(set) var itrSkipped: Bool
    
    var suiteName: String { suite.name }
    var moduleName: String { suite.moduleName }

    init(name: String, suite: DDTestSuite, startTime: Date? = nil) {
        let testStartTime = startTime ?? DDTestMonitor.clock.now
        self.name = name
        self.suite = suite
        self.status = .pass
        self.isUITest = false
        self.itrSkipped = false

        currentTestExecutionOrder = suite.currentExecutionOrder

        let attributes: [String: String] = [
            DDGenericTags.type: DDTagValues.typeTest,
            DDGenericTags.resource: "\(suite.name).\(name)",
            DDTestTags.testName: name,
            DDTestTags.testSuite: suite.name,
            DDTestTags.testFramework: suite.testFramework,
            DDTestTags.testType: DDTagValues.typeTest,
            DDTestTags.testExecutionOrder: "\(currentTestExecutionOrder)",
            DDTestTags.testExecutionProcessId: "\(initialProcessId)",
            DDTestTags.testIsUITest: "false",
            DDTestSuiteVisibilityTags.testSessionId: suite.suiteId.session.hexString,
            DDTestSuiteVisibilityTags.testModuleId: suite.suiteId.module.hexString,
            DDTestSuiteVisibilityTags.testSuiteId: suite.suiteId.suite.hexString,
            DDUISettingsTags.uiSettingsSuiteLocalization: suite.localization,
            DDUISettingsTags.uiSettingsModuleLocalization: suite.module.localization,
        ].merging(DDTestMonitor.baseConfigurationTags) { old, _ in old }

        span = DDTestMonitor.tracer.startSpan(name: "\(suite.testFramework).test", attributes: attributes, startTime: testStartTime)

        super.init()

        DDTestMonitor.tracer.addPropagationsHeadersToEnvironment()
        span.addTags(from: DDTestMonitor.env)

        let functionName = suite.name + "." + name
        if let functionInfo = suite.moduleFunctionInfo[functionName] {
            var filePath = functionInfo.file
            if let workspacePath = DDTestMonitor.env.workspacePath,
               let workspaceRange = filePath.range(of: workspacePath + "/")
            {
                filePath.removeSubrange(workspaceRange)
            }
            span.setAttribute(key: DDTestTags.testSourceFile, value: filePath)
            span.setAttribute(key: DDTestTags.testSourceStartLine, value: functionInfo.startLine)
            span.setAttribute(key: DDTestTags.testSourceEndLine, value: functionInfo.endLine)
            if let owners = suite.codeOwners?.ownersForPath(filePath) {
                span.setAttribute(key: DDTestTags.testCodeowners, value: owners)
            }
        }
        
        if let correlationId = DDTestMonitor.instance?.itr?.correlationId {
            span.setAttribute(key: DDItrTags.itrCorrelationId, value: correlationId)
        }

        if let coverageHelper = DDTestMonitor.instance?.coverageHelper {
            coverageHelper.setTest(name: name,
                                   testSessionId: suite.suiteId.session.rawValue,
                                   testSuiteId: suite.suiteId.suite.rawValue,
                                   spanId: span.context.spanId.rawValue)
            coverageHelper.clearCounters()
        }
        suite.test(started: self)
    }

    func setIsUITest(_ value: Bool) {
        self.isUITest = value
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
        }
        suite.test(updated: self)
    }

    /// Adds a extra tag or attribute to the test, any number of tags can be reported
    /// - Parameters:
    ///   - key: The name of the tag, if a tag exists with the name it will be
    ///     replaced with the new value
    ///   - value: The value of the tag, can be a number or a string.
    @objc public func setTag(key: String, value: Any) {
        span.setAttribute(key: key, value: AttributeValue(value))
        suite.test(updated: self)
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
    @objc public func end(status: DDTestStatus, endTime: Date? = nil) {
        self.end(status: status.itr, endTime: endTime)
    }

    @objc public func end(status: DDTestStatus) {
        self.end(status: status, endTime: nil)
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
}

extension DDTest {
    func end(status: DDTestStatus.ITR, endTime: Date? = nil) {
        let testEndTime = endTime ?? DDTestMonitor.clock.now
        self.status = status
        switch status {
        case .pass:
            span.setAttribute(key: DDTestTags.testStatus, value: DDTagValues.statusPass)
            span.status = .ok
        case .fail:
            span.setAttribute(key: DDTestTags.testStatus, value: DDTagValues.statusFail)
            span.status = .error(description: "Test failed")
            setErrorInformation()
        case .skip(itr: let itr):
            span.setAttribute(key: DDTestTags.testStatus, value: DDTagValues.statusSkip)
            if itr {
                span.setAttribute(key: DDTestTags.testSkippedByITR, value: true)
                itrSkipped = true
            }
            span.status = .ok
        }

        if let coverageHelper = DDTestMonitor.instance?.coverageHelper {
            coverageHelper.writeProfile()
            
            let testSessionId = suite.suiteId.session.rawValue
            let testSuiteId = suite.suiteId.suite.rawValue
            let spanId = span.context.spanId.rawValue
            let coverageFileURL = coverageHelper.getURLForTest(name: name, testSessionId: testSessionId, testSuiteId: testSuiteId, spanId: spanId)
            coverageHelper.coverageWorkQueue.addOperation {
                guard FileManager.default.fileExists(atPath: coverageFileURL.path) else {
                    return
                }
                DDTestMonitor.tracer.eventsExporter?.export(coverage: coverageFileURL, testSessionId: testSessionId, testSuiteId: testSuiteId, spanId: spanId, workspacePath: DDTestMonitor.env.workspacePath, binaryImagePaths: BinaryImages.binaryImagesPath)
            }
        }
        StderrCapture.syncData()
        span.end(time: testEndTime)
        DDTestMonitor.instance?.networkInstrumentation?.endAndCleanAliveSpans()
        suite.test(ended: self)
    }
    
    var spanData: SpanData? { (span as? ReadableSpan)?.toSpanData() }
}

extension DDTestStatus {
    enum ITR: Equatable {
        case pass
        case fail
        case skip(itr: Bool)
    }
    
    var itr: ITR {
        switch self {
        case .pass: return .pass
        case .fail: return .fail
        case .skip: return .skip(itr: false)
        }
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
