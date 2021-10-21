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

    init(bundleName: String, startTime: Date?) {
        if DDTestMonitor.instance == nil {
            DDTestMonitor.installTestMonitor()
        }

        self.bundleName = bundleName
#if !os(tvOS) && (targetEnvironment(simulator) || os(macOS))
        DDSymbolicator.createDSYMFileIfNeeded(forImageName: bundleName)
        bundleFunctionInfo = FileLocator.testFunctionsInModule(bundleName)
#endif
        if let workspacePath = DDTestMonitor.env.workspacePath {
            codeOwners = CodeOwners(workspacePath: URL(fileURLWithPath: workspacePath))
        }

        if !DDTestMonitor.env.disableCrashHandler {
            DDCrashes.install()
        }
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

public class DDTest: NSObject {
    static let testNameRegex = try! NSRegularExpression(pattern: "([\\w]+) ([\\w]+)", options: .caseInsensitive)
    static let supportsSkipping = NSClassFromString("XCTSkippedTestContext") != nil
    var currentTestExecutionOrder = 0
    var initialProcessId = Int(ProcessInfo.processInfo.processIdentifier)

    var span: Span

    var session: DDTestSession

    init(name: String, suite: DDTestSuite, session: DDTestSession, startTime: Date? = nil) {
        self.session = session

        currentTestExecutionOrder = currentTestExecutionOrder + 1
        let attributes: [String: String] = [
            DDGenericTags.type: DDTagValues.typeTest,
            DDGenericTags.resourceName: "\(suite.name).\(name)",
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
            DDCILibraryTags.ciLibraryLanguage: "swift",
            DDCILibraryTags.ciLibraryVersion: DDTestObserver.tracerVersion
        ]

        span = DDTestMonitor.tracer.startSpan(name: "\(session.testFramework).test", attributes: attributes, startTime: startTime)

        super.init()
        DDTestMonitor.instance?.currentTest = self

        // Is not a UITest until a XCUIApplication is launched
        span.setAttribute(key: DDTestTags.testIsUITest, value: false)

        if !DDTestMonitor.env.disableDDSDKIOSIntegration {
            DDTestMonitor.tracer.addPropagationsHeadersToEnvironment()
        }

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
    }

    /// Adds a extra atribute or tag to the test, any number of attributes can be reported
    /// - Parameters:
    ///   - key: The name of the attribute, if an atrtribute exists with the name it will be
    ///     replaced with the new value
    ///   - value: The value of the attibute, can be a number or a string.
    @objc public func setAttribute(key: String, value: Any) {
        span.setAttribute(key: key, value: AttributeValue(value))
    }

    /// Adds error information to the test, only one erros info can  be reported by a test
    /// - Parameters:
    ///   - type: The type of error to be reported
    ///   - message: The message associated with the error
    ///   - callstack: (Optional) The callstack associated with the error
    @objc public func setErrorInfo(type: String, message: String, callstack: String? = nil) {
        span.setAttribute(key: DDTags.errorType, value: AttributeValue.string(type))
        span.setAttribute(key: DDTags.errorMessage, value: AttributeValue.string(message))
        if let callstack = callstack {
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
            case .skip:
                testStatus = DDTagValues.statusSkip
                span.status = .ok
        }

        span.setAttribute(key: DDTestTags.testStatus, value: testStatus)
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
    @objc public func addBenchmark(name: String, samples: [Double], info: String?) {
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
