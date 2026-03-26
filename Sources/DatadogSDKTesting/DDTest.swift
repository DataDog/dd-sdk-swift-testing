/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@preconcurrency internal import OpenTelemetryApi
@preconcurrency internal import OpenTelemetrySdk
internal import SigmaSwiftStatistics

@objc(DDTest)
public final class Test: NSObject {
    let name: String
    let span: SpanSdk

    let suite: TestSuite

    private let errorInfo: Synced<ErrorInfo?> = .init(nil)
    
    init(name: String, suite: TestSuite, span: SpanSdk) {
        self.name = name
        self.span = span
        self.suite = suite
    }

    func setIsUITest(_ value: Bool) {
        self.span.setAttribute(key: DDTestTags.testIsUITest, value: value ? "true" : "false")

        // Set default UI values if nor previously set
        let attributes = span.getAttributes()
        if attributes[DDUISettingsTags.uiSettingsAppearance] == nil {
            setTag(key: DDUISettingsTags.uiSettingsAppearance, value: PlatformUtils.getAppearance())
        }
#if os(iOS)
        if attributes[DDUISettingsTags.uiSettingsOrientation] == nil {
            setTag(key: DDUISettingsTags.uiSettingsOrientation, value: PlatformUtils.getOrientation())
        }
#endif
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
        errorInfo.update { errorInfo in
            if errorInfo == nil {
                errorInfo = ErrorInfo(type: type, message: message, callstack: callstack)
            } else {
                errorInfo?.addExtraError(message: message)
            }
        }
        DDTestMonitor.tracer.logError(string: "\(type): \(message)")
    }

    private func setErrorInformation() {
        guard let errorInfo = errorInfo.value else { return }
        span.setAttribute(key: DDTags.errorType, value: errorInfo.type)
        span.setAttribute(key: DDTags.errorMessage, value: errorInfo.message)
        if let callstack = errorInfo.callstack {
            span.setAttribute(key: DDTags.errorStack, value: callstack)
        }
    }

    /// Ends the test
    /// - Parameters:
    ///   - status: the status reported for this test
    ///   - endTime: Optional, the time where the test ended
    @objc public func end(status: TestStatus, endTime: Date) {
        set(status: status)
        internalEnd(endTime: endTime)
    }

    /// Sets status for the test
    /// - Parameters:
    ///   - status: the status reported for this test
    @objc public func set(status: TestStatus) {
        switch status {
        case .pass:
            span.setAttribute(key: DDTestTags.testStatus, value: DDTagValues.statusPass)
            span.status = .ok
        case .fail:
            span.setAttribute(key: DDTestTags.testStatus, value: DDTagValues.statusFail)
            setErrorInformation()
            span.status = .error(description: "Test failed")
        case .skip:
            span.setAttribute(key: DDTestTags.testStatus, value: DDTagValues.statusSkip)
            span.status = .ok
        }
    }

    /// Adds benchmark information to the test, it also changes the test to be of type
    /// benchmark
    /// - Parameters:
    ///   - name: Name of the measure benchmarked
    ///   - samples: Array for values sampled for the measure
    ///   - info: (Optional) Extra information about the benchmark
    @objc func addBenchmarkData(name: String, samples: [Double], info: String?) {
        add(benchmark: name, samples: samples, info: info)
    }
    
    /// Current active test
    @objc public static var current: Test? { Self.active as? Test }
}

extension Test: TestRun {
    var id: SpanId { span.context.spanId }
    var startTime: Date { span.startTime }
    var duration: UInt64 { span.endTime?.timeIntervalSince(span.startTime).toNanoseconds ?? 0 }
    
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
}

extension Test {
    func internalEnd(endTime: Date) {
        guard span.endTime == nil else { return }
        StderrCapture.syncData()
        span.end(time: endTime)
        DDTestMonitor.instance?.networkInstrumentation?.endAndCleanAliveSpans()
    }
    
    static func withActiveTest<T>(named name: String, in suite: Suite, at start: Date? = nil,
                               _ action: @Sendable (Self) async throws -> T) async rethrows -> T
    {
        let testStartTime = start ?? suite.configuration.clock.now
        return try await DDTestMonitor.tracer.withActiveSpan(name: "\(suite.testFramework).test",
                                                             attributes: attributes(test: name, in: suite),
                                                             startTime: testStartTime) { span in
            let test = Self(name: name, suite: suite, span: span)
            let result = try await test.withActive {
                try await action(test)
            }
            test.internalEnd(endTime: suite.configuration.clock.now)
            return result
        }
    }
    
    static func withActiveTest<T>(named name: String, in suite: Suite, at start: Date? = nil,
                               _ action: (Self) throws -> T) rethrows -> T
    {
        let testStartTime = start ?? suite.configuration.clock.now
        return try DDTestMonitor.tracer.withActiveSpan(name: "\(suite.testFramework).test",
                                                       attributes: attributes(test: name, in: suite),
                                                       startTime: testStartTime) { span in
            let test = Self(name: name, suite: suite, span: span)
            let result = try test.withActive {
                try action(test)
            }
            test.internalEnd(endTime: suite.configuration.clock.now)
            return result
        }
    }
    
    static func attributes(test name: String, in suite: Suite) -> [String: AttributeValue] {
        var attributes: [String: AttributeValue] = [
            DDGenericTags.type: .string(DDTagValues.typeTest),
            DDGenericTags.resource: .string("\(suite.name).\(name)"),
            DDTestTags.testName: .string(name),
            DDTestTags.testSuite: .string(suite.name),
            DDTestTags.testModule: .string(suite.module.name),
            DDTestTags.testFramework: .string(suite.testFramework),
            DDTestTags.testType: .string(DDTagValues.typeTest),
            DDTestTags.testIsUITest: .string("false"),
            DDTestSuiteVisibilityTags.testSessionId: .string(suite.session.id.hexString),
            DDTestSuiteVisibilityTags.testModuleId: .string(suite.module.id.hexString),
            DDTestSuiteVisibilityTags.testSuiteId: .string(suite.id.hexString),
            DDUISettingsTags.uiSettingsSuiteLocalization: .string(suite.localization),
            DDUISettingsTags.uiSettingsModuleLocalization: .string(suite.module.localization),
            DDTestTags.testExecutionOrder: .int(Int(suite.session.nextTestIndex())),
            DDTestTags.testExecutionProcessId: .int(Int(ProcessInfo.processInfo.processIdentifier))
        ]
        
        // TODO: Move to common medatada when we will have common metrics
        for metric in suite.configuration.metrics {
            attributes[metric.key] = .double(metric.value)
        }
        
        return attributes
    }
    
    static func withActiveTest<T>(named name: String, in suite: Suite, at start: Date? = nil,
                               _ action: @Sendable (Self) async throws -> T) async rethrows -> T
    {
        let testStartTime = start ?? suite.configuration.clock.now
        return try await DDTestMonitor.tracer.withActiveSpan(name: "\(suite.testFramework).test",
                                                             attributes: attributes(test: name, in: suite),
                                                             startTime: testStartTime) { span in
            let test = Self(name: name, suite: suite, span: span)
            let result = try await test.withActive {
                try await action(test)
            }
            test.internalEnd(endTime: suite.configuration.clock.now)
            return result
        }
    }
    
    static func withActiveTest<T>(named name: String, in suite: Suite, at start: Date? = nil,
                               _ action: (Self) throws -> T) rethrows -> T
    {
        let testStartTime = start ?? suite.configuration.clock.now
        return try DDTestMonitor.tracer.withActiveSpan(name: "\(suite.testFramework).test",
                                                       attributes: attributes(test: name, in: suite),
                                                       startTime: testStartTime) { span in
            let test = Self(name: name, suite: suite, span: span)
            let result = try test.withActive {
                try action(test)
            }
            test.internalEnd(endTime: suite.configuration.clock.now)
            return result
        }
    }
    
    static func attributes(test name: String, in suite: Suite) -> [String: AttributeValue] {
        var attributes: [String: AttributeValue] = [
            DDGenericTags.type: .string(DDTagValues.typeTest),
            DDGenericTags.resource: .string("\(suite.name).\(name)"),
            DDTestTags.testName: .string(name),
            DDTestTags.testSuite: .string(suite.name),
            DDTestTags.testModule: .string(suite.module.name),
            DDTestTags.testFramework: .string(suite.testFramework),
            DDTestTags.testType: .string(DDTagValues.typeTest),
            DDTestTags.testIsUITest: .string("false"),
            DDTestSuiteVisibilityTags.testSessionId: .string(suite.session.id.hexString),
            DDTestSuiteVisibilityTags.testModuleId: .string(suite.module.id.hexString),
            DDTestSuiteVisibilityTags.testSuiteId: .string(suite.id.hexString),
            DDUISettingsTags.uiSettingsSuiteLocalization: .string(suite.localization),
            DDUISettingsTags.uiSettingsModuleLocalization: .string(suite.module.localization),
            DDTestTags.testExecutionOrder: .int(Int(suite.session.nextTestIndex())),
            DDTestTags.testExecutionProcessId: .int(Int(ProcessInfo.processInfo.processIdentifier))
        ]
        
        // TODO: Move to common medatada when we will have common metrics
        for metric in suite.configuration.metrics {
            attributes[metric.key] = .double(metric.value)
        }
        
        return attributes
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
