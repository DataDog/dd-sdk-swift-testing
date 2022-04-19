/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
@_implementationOnly import OpenTelemetryApi
@_implementationOnly import OpenTelemetrySdk
@_implementationOnly import SigmaSwiftStatistics

public class DDTestSession: NSObject {
    var bundleName = ""
    var bundleFunctionInfo = FunctionMap()
    var codeOwners: CodeOwners?
    var testFramework = "Swift API"

    private let executionLock = NSLock()
    private var privateCurrentExecutionOrder = 0
    var currentExecutionOrder: Int {
        executionLock.lock()
        defer {
            privateCurrentExecutionOrder += 1
            executionLock.unlock()
        }
        return privateCurrentExecutionOrder
    }

    init(bundleName: String, startTime: Date?) {
        if DDTestMonitor.instance == nil {
            DDTestMonitor.installTestMonitor()
        }

        self.bundleName = bundleName
#if targetEnvironment(simulator) || os(macOS)
        DDSymbolicator.createDSYMFileIfNeeded(forImageName: bundleName)
        bundleFunctionInfo = FileLocator.testFunctionsInModule(bundleName)
#endif
        if let workspacePath = DDTestMonitor.env.workspacePath {
            codeOwners = CodeOwners(workspacePath: URL(fileURLWithPath: workspacePath))
        }

        if !DDTestMonitor.env.disableCrashHandler {
            DDCrashes.install()
        }

        DDCoverageHelper.instance = DDCoverageHelper()
    }

    func internalEnd(endTime: Date? = nil) {
        /// We need to wait for all the traces to be written to the backend before exiting
        DDTestMonitor.tracer.flush()
    }
}

@objc public enum DDTestStatus: Int {
    case pass
    case fail
    case skip
}

/// Public interface for DDTestSession
public extension DDTestSession {
    /// Starts the session
    /// - Parameters:
    ///   - bundleName: name of the module or bundle to test.
    ///   - startTime: Optional, the time where the session started
    @objc static func start(bundleName: String, startTime: Date? = nil) -> DDTestSession {
        let session = DDTestSession(bundleName: bundleName, startTime: startTime)
        return session
    }

    @objc static func start(bundleName: String) -> DDTestSession {
        return start(bundleName: bundleName, startTime: nil)
    }

    /// Ends the session
    /// - Parameters:
    ///   - endTime: Optional, the time where the session ended
    @objc(endWithTime:) func end(endTime: Date? = nil) {
        internalEnd(endTime: endTime)
    }

    @objc func end() {
        return end(endTime: nil)
    }

    /// Adds a extra tag or attribute to the test session, any number of tags can be reported
    /// - Parameters:
    ///   - key: The name of the tag, if a tag exists with the name it will be
    ///     replaced with the new value
    ///   - value: The value of the tag, can be a number or a string.
    @objc func setTag(key: String, value: Any) {}

    /// Starts a suite in this session
    /// - Parameters:
    ///   - name: name of the suite
    ///   - startTime: Optional, the time where the suite started
    @objc func suiteStart(name: String, startTime: Date? = nil) -> DDTestSuite {
        let suite = DDTestSuite(name: name, session: self, startTime: startTime)
        return suite
    }

    @objc func suiteStart(name: String) -> DDTestSuite {
        return suiteStart(name: name, startTime: nil)
    }
}

public class DDTestSuite: NSObject {
    var name: String
    var session: DDTestSession

    init(name: String, session: DDTestSession, startTime: Date? = nil) {
        self.name = name
        self.session = session
    }

    /// Ends the test suite
    /// - Parameters:
    ///   - endTime: Optional, the time where the suite ended
    @objc(endWithTime:) public func end(endTime: Date? = nil) {}
    @objc public func end() {}

    /// Adds a extra tag or attribute to the test suite, any number of tags can be reported
    /// - Parameters:
    ///   - key: The name of the tag, if a tag exists with the name it will be
    ///     replaced with the new value
    ///   - value: The value of the tag, can be a number or a string.
    @objc public func setTag(key: String, value: Any) {}

    /// Starts a test in this suite
    /// - Parameters:
    ///   - name: name of the suite
    ///   - startTime: Optional, the time where the test started
    @objc public func testStart(name: String, startTime: Date? = nil) -> DDTest {
        return DDTest(name: name, suite: self, session: session, startTime: startTime)
    }

    @objc public func testStart(name: String) -> DDTest {
        return testStart(name: name, startTime: nil)
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

public class DDTest: NSObject {
    static let testNameRegex = try! NSRegularExpression(pattern: "([\\w]+) ([\\w]+)", options: .caseInsensitive)
    static let supportsSkipping = NSClassFromString("XCTSkippedTestContext") != nil
    var currentTestExecutionOrder: Int
    var initialProcessId = Int(ProcessInfo.processInfo.processIdentifier)
    let name: String
    var span: Span

    var session: DDTestSession

    private var errorInfo: ErrorInfo?

    init(name: String, suite: DDTestSuite, session: DDTestSession, startTime: Date? = nil) {
        self.name = name
        self.session = session

        currentTestExecutionOrder = session.currentExecutionOrder

        let attributes: [String: String] = [
            DDGenericTags.type: DDTagValues.typeTest,
            DDGenericTags.resourceName: "\(suite.name).\(name)",
            DDGenericTags.language: "swift",
            DDTestTags.testName: name,
            DDTestTags.testSuite: suite.name,
            DDTestTags.testFramework: session.testFramework,
            DDTestTags.testBundle: session.bundleName,
            DDTestTags.testType: DDTagValues.typeTest,
            DDTestTags.testExecutionOrder: "\(currentTestExecutionOrder)",
            DDTestTags.testExecutionProcessId: "\(initialProcessId)",
            DDOSTags.osPlatform: DDTestMonitor.env.osName,
            DDOSTags.osArchitecture: DDTestMonitor.env.osArchitecture,
            DDOSTags.osVersion: DDTestMonitor.env.osVersion,
            DDDeviceTags.deviceName: DDTestMonitor.env.deviceName,
            DDDeviceTags.deviceModel: DDTestMonitor.env.deviceModel,
            DDRuntimeTags.runtimeName: DDTestMonitor.env.runtimeName,
            DDRuntimeTags.runtimeVersion: DDTestMonitor.env.runtimeVersion,
            DDGenericTags.library_version: DDTestObserver.tracerVersion,
        ]

        span = DDTestMonitor.tracer.startSpan(name: "\(session.testFramework).test", attributes: attributes, startTime: startTime)

        super.init()
        DDTestMonitor.instance?.currentTest = self

        // Is not a UITest until a XCUIApplication is launched
        span.setAttribute(key: DDTestTags.testIsUITest, value: "false")

        DDTestMonitor.tracer.addPropagationsHeadersToEnvironment()

        let functionName = suite.name + "." + name
        if let functionInfo = session.bundleFunctionInfo[functionName] {
            var filePath = functionInfo.file
            if let workspacePath = DDTestMonitor.env.workspacePath,
               let workspaceRange = filePath.range(of: workspacePath + "/")
            {
                filePath.removeSubrange(workspaceRange)
            }
            span.setAttribute(key: DDTestTags.testSourceFile, value: filePath)
            span.setAttribute(key: DDTestTags.testSourceStartLine, value: functionInfo.startLine)
            span.setAttribute(key: DDTestTags.testSourceEndLine, value: functionInfo.endLine)
            if let owners = session.codeOwners?.ownersForPath(filePath) {
                span.setAttribute(key: DDTestTags.testCodeowners, value: owners)
            }
        }

        DDTestMonitor.env.addTagsToSpan(span: span)

        if let testSpan = span as? RecordEventsReadableSpan {
            let simpleSpan = SimpleSpanData(spanData: testSpan.toSpanData())
            DDCrashes.setCustomData(customData: SimpleSpanSerializer.serializeSpan(simpleSpan: simpleSpan))
        }

        DDCoverageHelper.instance?.setTest(name: name,
                                           traceId: span.context.traceId.hexString)
        DDCoverageHelper.instance?.clearCounters()
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
    /// will be shown in the error messages. If stdout or stderr instrumentation is enabled, errors will also be logged.
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
        let testStatus: String
        switch status {
            case .pass:
                testStatus = DDTagValues.statusPass
                span.status = .ok
            case .fail:
                testStatus = DDTagValues.statusFail
                span.status = .error(description: "Test failed")
                setErrorInformation()
            case .skip:
                testStatus = DDTagValues.statusSkip
                span.status = .ok
        }

        span.setAttribute(key: DDTestTags.testStatus, value: testStatus)

        let endTime: Date? = Date()

        var start, llvmProfDataTime, llvmCovTime, llvmTime, ddCoverageTime: DispatchTime

        DDCoverageHelper.instance?.writeProfile()
        if let coverageFileURL = DDCoverageHelper.instance?.getPathForTest(name: name, traceId: span.context.traceId.hexString) {
            start = DispatchTime.now()
            let profData = DDCoverageConversor.generateProfData(profrawFile: coverageFileURL)
            llvmProfDataTime = DispatchTime.now()
            let covJson = DDCoverageConversor.getCoverageJson(profdataFile: profData, saveToFile: true)
            llvmCovTime = DispatchTime.now()
            if let llvmCoverage = LLVMCoverageFormat(fromURL: covJson) {
                llvmTime = DispatchTime.now()
                if let ddCoverage = DDCoverageFormat(llvmFormat: llvmCoverage, testId: span.context.traceId.hexString) {
                    ddCoverageTime = DispatchTime.now()
                    try? ddCoverage.jsonData?.write(to: coverageFileURL.deletingPathExtension().appendingPathExtension("json"))

                    let llvmProf = Double(llvmProfDataTime.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
                    let llvmCov = Double(llvmCovTime.uptimeNanoseconds - llvmProfDataTime.uptimeNanoseconds) / 1_000_000
                    let llvmJson = Double(llvmTime.uptimeNanoseconds - llvmCovTime.uptimeNanoseconds) / 1_000_000
                    let ddCov = Double(ddCoverageTime.uptimeNanoseconds - llvmTime.uptimeNanoseconds) / 1_000_000

                    span.setAttribute(key: "performance.llvmProf", value: llvmProf)
                    span.setAttribute(key: "performance.llvmCov", value: llvmCov)
                    span.setAttribute(key: "performance.llvmJson", value: llvmJson)
                    span.setAttribute(key: "performance.ddCov", value: ddCov)
                }
            }


        }

        StderrCapture.syncData()
        if let endTime = endTime {
            span.end(time: endTime)
        } else {
            span.end()
        }
        DDTestMonitor.tracer.backgroundWorkQueue.sync {}
        DDTestMonitor.instance?.currentTest = nil
        DDTestMonitor.instance?.networkInstrumentation?.endAndCleanAliveSpans()
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
    @objc func addBenchmark(name: String, samples: [Double], info: String?) {
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
