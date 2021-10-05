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

    public init(bundleName: String) {
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

    public func end() {
        /// We need to wait for all the traces to be written to the backend before exiting
        DDTestMonitor.tracer.flush()
    }
}

@objc public enum DDTestStatus: Int {
    case pass
    case fail
    case skip
}

public extension DDTestSession {
    // Public interface for DDTestSession

    @objc func suiteStart(name: String) -> DDTestSuite {
        let suite = DDTestSuite(name: name)
        return suite
    }

    @objc(suiteEnd:) func suiteEnd(suite: DDTestSuite) {
        suite.end()
    }

    @objc func testStart(name: String, suite: DDTestSuite) -> DDTest {
        return DDTest(name: name, suite: suite, session: self)
    }

    @objc(testSetAttribute:key:value:) func testSetAttribute(test: DDTest, key: String, value: Any) {
        test.setAttribute(key: key, value: value)
    }

    @objc(testSetErrorInfo:type:message:callstack:) func testSetErrorInfo(test: DDTest, type: String, message: String, callstack: String?) {
        test.setErrorInfo(type: type, message: message, callstack: callstack)
    }

    @objc(testAddBenchmark:name:samples:info:) func testAddBenchmark(test:DDTest, name: String, samples: [Double], info: String?) {
        test.addBenchmark(name: name, samples: samples, info: info)
    }

    @objc(testEnd:status:) func testEnd(test: DDTest, status: DDTestStatus) {
        test.end(status: status)
    }

}

public class DDTestSuite: NSObject {
    var name: String

    init(name: String) {
        self.name = name
    }

    func end() {}
}

public class DDTest: NSObject {
    static let testNameRegex = try! NSRegularExpression(pattern: "([\\w]+) ([\\w]+)", options: .caseInsensitive)
    static let supportsSkipping = NSClassFromString("XCTSkippedTestContext") != nil
    var currentTestExecutionOrder = 0
    var initialProcessId = Int(ProcessInfo.processInfo.processIdentifier)

    var span: Span

    var session: DDTestSession

    init(name: String, suite: DDTestSuite, session: DDTestSession) {
        self.session = session

        currentTestExecutionOrder = currentTestExecutionOrder + 1
        let attributes: [String: String] = [
            DDGenericTags.type: DDTagValues.typeTest,
            DDGenericTags.resourceName: "\(session.bundleName).\(suite.name).\(name)",
            DDTestTags.testName: name,
            DDTestTags.testSuite: suite.name,
            DDTestTags.testFramework: "XCTest",
            DDTestTags.testBundle: session.bundleName,
            DDTestTags.testType: DDTagValues.typeTest,
            DDTestTags.testExecutionOrder: "\(currentTestExecutionOrder)",
            DDTestTags.testExecutionProcessId: "\(initialProcessId)",
            DDOSTags.osPlatform: DDTestMonitor.env.osName,
            DDOSTags.osArchitecture: DDTestMonitor.env.osArchitecture,
            DDOSTags.osVersion: DDTestMonitor.env.osVersion,
            DDDeviceTags.deviceName: DDTestMonitor.env.deviceName,
            DDDeviceTags.deviceModel: DDTestMonitor.env.deviceModel,
            DDRuntimeTags.runtimeName: "Xcode",
            DDRuntimeTags.runtimeVersion: DDTestMonitor.env.runtimeVersion,
            DDCILibraryTags.ciLibraryLanguage: "swift",
            DDCILibraryTags.ciLibraryVersion: DDTestObserver.tracerVersion
        ]

        span = DDTestMonitor.tracer.startSpan(name: "\(suite.name).\(name)()", attributes: attributes)

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

    func setAttribute(key: String, value: Any) {
        span.setAttribute(key: key, value: AttributeValue(value))
    }

    func setErrorInfo(type: String, message: String, callstack: String?) {
        span.setAttribute(key: DDTags.errorType, value: AttributeValue.string(type))
        span.setAttribute(key: DDTags.errorMessage, value: AttributeValue.string(message))
        if let callstack = callstack {
            span.setAttribute(key: DDTags.errorStack, value: AttributeValue.string(callstack))
        }
    }

    func end(status: DDTestStatus) {
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
        span.end()
        DDTestMonitor.tracer.backgroundWorkQueue.sync {}
        DDTestMonitor.instance?.currentTest = nil
        DDTestMonitor.instance?.networkInstrumentation?.endAndCleanAliveSpans()
    }

    func addBenchmark(name: String, samples: [Double], info: String?) {
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
