/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import OpenTelemetryApi
internal import SigmaSwiftStatistics

protocol TestModel: AnyObject, Sendable {
    var id: SpanId { get }
    var name: String { get }
    var startTime: Date { get }
    var duration: UInt64 { get }
    var status: TestStatus { get }
    
    func set(tag name: String, value: any SpanAttributeConvertible)
    func set(metric name: String, value: Double)
}

protocol TestContainer: TestModel {
    func set(failed reason: TestError?)
    func set(skipped reason: String?)
    
    func end()
    func end(time: Date?)
}

extension TestContainer {
    func end() { end(time: nil) }
}

protocol TestSession: TestContainer {
    var testFrameworks: Set<String> { get }
    func nextTestIndex() -> UInt
}

protocol TestSessionManagerObserver: Sendable, Identifiable<ObjectIdentifier> {
    func willStart(session: any TestSession, with config: SessionConfig) async
    func didFinish(session: any TestSession, with config: SessionConfig) async
}

protocol TestSessionProvider: Sendable {
    func startSession(named: String, config: SessionConfig, startTime: Date) async throws -> any TestSession & TestModuleProvider
}

protocol TestSessionManager: Sendable {
    var session: any TestSession & TestModuleProvider { get async throws }
    var sessionConfig: SessionConfig { get async throws }
    
    func add(observer: any TestSessionManagerObserver) async
    func remove(observer: any TestSessionManagerObserver) async
    
    func stop() async
}

protocol TestModule: TestContainer {
    var session: any TestSession { get }
    var testFrameworks: Set<String> { get }
    var localization: String { get }
}

protocol TestModuleProvider: Sendable {
    func startModule(named: String) -> any TestModule & TestSuiteProvider
}

protocol TestSuite: TestContainer {
    var session: any TestSession { get }
    var module: any TestModule { get }
    var localization: String { get }
    var testFramework: String { get }
}

protocol TestSuiteProvider: Sendable {
    func startSuite(named: String, framework: String) -> any TestSuite & TestRunProvider
}

protocol TestRunProvider: Sendable {
    func startTest(named: String) -> any TestRun
}

extension TestSuite {
    var session: any TestSession { module.session }
    
    func set(status: TestStatus) {
        switch status {
        case .fail: set(failed: nil)
        case .skip: set(skipped: nil)
        case .pass: break
        }
    }
}

protocol TestRun: TestModel {
    var session: any TestSession { get }
    var module: any TestModule { get }
    var suite: any TestSuite { get }
    
    func add(error: TestError)
    func add(benchmark name: String, samples: [Double], info: String?)
    
    func end(status: TestStatus)
    func end(status: TestStatus, time: Date?)
}

extension TestRun {
    var session: any TestSession { suite.session }
    var module: any TestModule { suite.module }
    
    func end(status: TestStatus) { end(status: status, time: nil) }
}

@objc(DDTestStatus)
public enum TestStatus: Int {
    case pass
    case fail
    case skip
    
    func final(ignoreErrors: Bool) -> Self {
        self == .fail && ignoreErrors ? .pass : self
    }
}

extension TestStatus: SpanAttributeConvertible {
    var spanAttribute: String {
        switch self {
        case .pass: return DDTagValues.statusPass
        case .fail: return DDTagValues.statusFail
        case .skip: return DDTagValues.statusSkip
        }
    }
}

extension TestStatus: CustomDebugStringConvertible {
    public var debugDescription: String { spanAttribute }
}

struct TestError {
    let type: String
    let message: String?
    let stack: String?
    let crashLog: String?
    
    init(type: String, message: String? = nil, stack: String? = nil, crashLog: String? = nil) {
        self.type = type
        self.message = message
        self.stack = stack
        self.crashLog = crashLog
    }
}

struct SessionConfig {
    let activeFeatures: [any TestHooksFeature]
    let clock: Clock
    let crash: CrashedModuleInformation?
    let command: String?
}

extension TestModel {
    internal var endTime: Date {
        startTime.addingTimeInterval(.fromNanoseconds(Int64(duration)))
    }
    
    /// saves error tags to the model
    internal func set(errorTags error: TestError) {
        set(tag: DDTags.errorType, value: error.type)
        if let message = error.message {
            set(tag: DDTags.errorMessage, value: message)
        }
        if let stack = error.stack {
            set(tag: DDTags.errorStack, value: stack)
        }
        if let crash = error.crashLog {
            set(tag: DDTags.errorCrashLog, value: crash)
        }
    }
    
    internal func trySet(tag key: String, value: Any) {
        if let value = value as? any BinaryFloatingPoint {
            self.set(metric: key, value: Double(value))
        } else if let value = value as? any BinaryInteger {
            self.set(metric: key, value: Double(value))
        } else if let value = value as? SpanAttributeConvertible {
            self.set(tag: key, value: value)
        }
    }
}

extension TestRun {
    func add(benchmark name: String, samples: [Double], info: String?) {
        set(tag:  DDTestTags.testType, value: DDTagValues.typeBenchmark)

        let tag = DDBenchmarkTags.benchmark + "." + name + "."

        if let benchmarkInfo = info {
            self.set(tag: tag + DDBenchmarkTags.benchmarkInfo, value: benchmarkInfo)
        }
        set(metric: tag + DDBenchmarkTags.benchmarkRun, value: Double(samples.count))
        set(metric: tag + DDBenchmarkTags.statisticsN, value: Double(samples.count))
        if let average = Sigma.average(samples) {
            set(metric: tag + DDBenchmarkTags.benchmarkMean, value: average)
        }
        if let max = Sigma.max(samples) {
            set(metric: tag + DDBenchmarkTags.statisticsMax, value: max)
        }
        if let min = Sigma.min(samples) {
            set(metric: tag + DDBenchmarkTags.statisticsMin, value: min)
        }
        if let mean = Sigma.average(samples) {
            set(metric: tag + DDBenchmarkTags.statisticsMean, value: mean)
        }
        if let median = Sigma.median(samples) {
            set(metric: tag + DDBenchmarkTags.statisticsMedian, value: median)
        }
        if let stdDev = Sigma.standardDeviationSample(samples) {
            set(metric: tag + DDBenchmarkTags.statisticsStdDev, value: stdDev)
        }
        if let stdErr = Sigma.standardErrorOfTheMean(samples) {
            set(metric: tag + DDBenchmarkTags.statisticsStdErr, value: stdErr)
        }
        if let kurtosis = Sigma.kurtosisA(samples), kurtosis.isFinite {
            set(metric: tag + DDBenchmarkTags.statisticsKurtosis, value: kurtosis)
        }
        if let skewness = Sigma.skewnessA(samples), skewness.isFinite {
            set(metric: tag + DDBenchmarkTags.statisticsSkewness, value: skewness)
        }
        if let percentile99 = Sigma.percentile(samples, percentile: 0.99) {
            set(metric: tag + DDBenchmarkTags.statisticsP99, value: percentile99)
        }
        if let percentile95 = Sigma.percentile(samples, percentile: 0.95) {
            set(metric: tag + DDBenchmarkTags.statisticsP95, value: percentile95)
        }
        if let percentile90 = Sigma.percentile(samples, percentile: 0.90) {
            set(metric: tag + DDBenchmarkTags.statisticsP90, value: percentile90)
        }
    }
}
