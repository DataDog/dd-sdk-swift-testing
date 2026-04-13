/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter
@preconcurrency internal import OpenTelemetryApi
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
    var tags: [String: String] { get }
    var metrics: [String: Double] { get }
    
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

protocol TestSessionManagerObserver: Sendable {
    func didStart(session: any TestSession, with config: SessionConfig) async
    func willFinish(session: any TestSession, with config: SessionConfig) async
    func didFinish(session: any TestSession, with config: SessionConfig) async
}

protocol TestSessionProvider: Sendable {
    func startSession(named: String, config: SessionConfig, startTime: Date,
                      observer: (any TestModuleManagerObserver)?) async throws -> any TestSession & TestModuleManager
}

protocol TestSessionManager: Sendable {
    var session: any TestSession & TestModuleManager { get async throws }
    var config: SessionConfig { get async throws }
    var sessionAndConfig: (session: any TestSession & TestModuleManager, config: SessionConfig) { get async throws }
    
    func stop() async
}

extension TestSessionManager {
    var session: any TestSession & TestModuleManager {
        get async throws { try await sessionAndConfig.session }
    }
    var config: SessionConfig {
        get async throws { try await sessionAndConfig.config }
    }
}

protocol TestModule: TestContainer {
    var session: any TestSession { get }
    var testFrameworks: Set<String> { get }
    var localization: String { get }
}

protocol TestModuleProvider: Sendable {
    func startModule(named: String, at: Date?) -> any TestModule & TestSuiteProvider
}

protocol TestModuleManagerObserver: Sendable {
    func didStart(module: any TestModule, with config: SessionConfig)
    func willFinish(module: any TestModule, with config: SessionConfig)
    func didFinish(module: any TestModule, with config: SessionConfig)
}

protocol TestModuleManager: Sendable {
    func module(named: String) -> any TestModule & TestSuiteProvider
    func end(module: any TestModule)
}

protocol TestSuite: TestContainer {
    var session: any TestSession { get }
    var module: any TestModule { get }
    var localization: String { get }
    var testFramework: String { get }
}

protocol TestSuiteProvider: Sendable {
    func startSuite(named: String, at: Date?, framework: String) -> any TestSuite & TestRunProvider
}

protocol TestRunProvider: Sendable {
    func withActiveTest<T>(named name: String, _ action: @Sendable (any TestRun) async throws -> T) async rethrows -> T
    func withActiveTest<T>(named name: String, _ action: (any TestRun) throws -> T) rethrows -> T
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
    
    func set(status: TestStatus)
    
    static var active: (any TestRun)? { get }
}

extension TestRun {
    var session: any TestSession { suite.session }
    var module: any TestModule { suite.module }
    
    static var active: (any TestRun)? { _activeTestRun }
    
    func withActive<T>(_ action: () throws -> T) rethrows -> T {
        try $_activeTestRun.withValue(self) {
            try action()
        }
    }
    
    func withActive<T>(_ action: @Sendable () async throws -> T) async rethrows -> T {
        try await $_activeTestRun.withValue(self) {
            try await action()
        }
    }
}

protocol TestTag {
    associatedtype Value
}

protocol TestTags {
    func get<T: TestTag>(tag: T) -> T.Value?
}

@objc(DDTestStatus)
public enum TestStatus: Int, Sendable {
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

struct TestError: Error, CustomDebugStringConvertible {
    let type: String
    let message: String?
    let stack: String?
    let crashLog: [String]?
    
    init(type: String, message: String? = nil, stack: String? = nil) {
        self.type = type
        guard let stack else {
            self.message = message
            self.stack = nil
            self.crashLog = nil
            return
        }
        if stack.count < 5000 {
            self.message = message
            self.stack = stack
            self.crashLog = nil
        } else {
            self.message = message.map { $0 + ". " } ?? ""
                + "Check error.crash_log for the full crash log."
            self.stack = DDSymbolicator.calculateCrashedThread(stack: stack)
            self.crashLog = stack.split(by: 5000)
        }
    }
    
    func joined(other error: Self) -> Self {
        var newMessage: String
        var newStack: String? = nil
        if let message {
            newMessage = message[message.startIndex] == "\n" ? message : "\n\(message)"
            newMessage += "\n>>> \(error.type)"
        } else {
            newMessage = "\n\n>>> \(error.type)"
        }
        if let message = error.message {
            newMessage += ": \(message)"
        }
        if let crashLog {
            newStack = crashLog.joined()
        } else {
            newStack = self.stack
        }
        if let log = error.crashLog {
            if newStack != nil {
                newStack! += "\n\n\(log.joined())"
            } else {
                newStack = "\(log.joined())"
            }
        } else if let stack = error.stack {
            if newStack != nil {
                newStack! += "\n\n\(stack)"
            } else {
                newStack = stack
            }
        }
        return .init(type: type, message: newMessage, stack: newStack)
    }
    
    var debugDescription: String {
        var text = type
        if let message { text += ": \(message)" }
        if let stack { text += "\n\(stack)" }
        if let crashLog { text += "\n\n" + crashLog.joined(separator: "\n") }
        return text
    }
}

struct SessionConfig: Sendable {
    let activeFeatures: TestHooksFeatures
    let platform: Environment.Platform
    let clock: Clock
    let crash: CrashInformation?
    let command: String?
    let service: String
    let metrics: [String: Double]
    let log: Logger
}

struct TestRunParameters: Encodable {
    let arguments: JSONGeneric
    let metadata: JSONGeneric?
    
    init(arguments: JSONGeneric, metadata: JSONGeneric?) {
        self.arguments = arguments
        self.metadata = metadata
    }
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
            for i in 0 ..< crash.count {
                set(tag: "\(DDTags.errorCrashLog).\(String(format: "%02d", i))",
                    value: crash[i])
            }
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
    
    func set(tag name: String, value: JSONGeneric) {
        switch value {
        case .nil: break
        case .int(let i): set(metric: name, value: Double(i))
        case .float(let n): set(metric: name, value: n)
        case .bool(let b): set(tag: name, value: b.spanAttribute)
        case .string(let s): set(tag: name, value: s)
        case .date(let d): set(tag: name, value: JSONGeneric.formatter.string(from: d))
        case .bytes(let b): set(tag: name, value: b.base64EncodedString())
        default: set(tag: name, value: value.debugDescription)
        }
    }
    
    func set(parameters: TestRunParameters) {
        guard let value = try? String(data: JSONEncoder().encode(parameters), encoding: .utf8) else { return }
        self.set(tag: DDTestTags.testParameters, value: value)
    }
    
}

@TaskLocal private var _activeTestRun: (any TestRun)? = nil
