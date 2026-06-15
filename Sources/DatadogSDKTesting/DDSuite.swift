/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@preconcurrency internal import OpenTelemetryApi
@preconcurrency internal import OpenTelemetrySdk
internal import EventsExporter

@objc
public final class DDSuite: NSObject {
    struct MutableState {
        var testsStarted: Int = 0
    }

    public let name: String
    public let testFramework: TestFramework
    public let localization: String

    var duration: UInt64 {
        span.endTime?.timeIntervalSince(span.startTime).toNanoseconds ?? 0
    }
    var status: TestStatus { span.testStatus }

    var id: SpanId { span.context.spanId }
    let span: SpanSdk
    var module: TestModule { _module }
    var startTime: Date { span.startTime }

    private let _module: DDModule
    private let _state: Synced<MutableState>

    init(name: String, module: DDModule, framework: TestFramework, startTime: Date? = nil) {
        self.name = name
        self._module = module
        self.testFramework = framework
        self.localization = PlatformUtils.getLocalization()

        let state = MutableState()
        let id: SpanId
        let actualStartTime: Date
        let isCrashed: Bool
        if let crash = module.configuration.crash?.suite, crash.name == name {
            isCrashed = true
            id = crash.id
            actualStartTime = crash.startTime
        } else {
            isCrashed = false
            id = SpanId.random()
            actualStartTime = startTime ?? module.configuration.clock.now
        }

        var attributes: [String: AttributeValue] = [
            DDTestTags.testSuite: .string(name),
            DDTestTags.testModule: .string(module.name),
            DDTestTags.testFramework: .string(framework.name),
            DDTestTags.testFrameworkVersion: .string(framework.version),
            DDUISettingsTags.uiSettingsSuiteLocalization: .string(localization),
            DDUISettingsTags.uiSettingsModuleLocalization: .string(module.localization),
        ]
        
        attributes.type = DDTagValues.typeSuiteEnd
        attributes.resource = name
        attributes.testSessionId = module.session.id
        attributes.testModuleId = module.id
        attributes.testSuiteId = id
        
        for (key, value) in module.configuration.env.baseMetrics {
            attributes[key] = .double(value)
        }

        let span = module.configuration.tracer.createLifecycleSpan(name: "\(framework.name).suite",
                                                                   spanId: id,
                                                                   startTime: actualStartTime,
                                                                   attributes: attributes)
        if isCrashed {
            span.applyStatus(.fail, errorDescription: "suite failed")
        }
        self.span = span

        self._state = .init(state)

        super.init()

        if let crash = module.configuration.crash?.suite,
           let error = crash.error, crash.name == name
        {
            set(failed: error)
        }
    }

    private func internalEnd(endTime: Date? = nil) {
        let endTime = endTime ?? configuration.clock.now
        let shouldExport = _state.use { $0.testsStarted > 0 }
        // Don't emit a `test_suite_end` event for suites in which no tests
        // actually ran. This happens for container types that only enclose
        // nested @Suite types, and for XCTest's empty wrapper suites.
        guard shouldExport else {
            Log.debug("Skipped suite_end event for empty suite \(name) (id: \(self.id))")
            return
        }

        // get-status -> set-status round-trip (see DDSession).
        span.applyStatus(span.testStatus, errorDescription: "suite failed")
        span.end(time: endTime)
        Log.debug("Exported suite_end event suiteId: \(self.id)")
    }

    func recordTestStarted() {
        _state.update { $0.testsStarted += 1 }
    }

    /// Ends the test suite
    /// - Parameters:
    ///   - endTime: Optional, the time where the suite ended
    @objc(endWithTime:) public func end(endTime: Date? = nil) { internalEnd(endTime: endTime) }
    @objc public func end() { internalEnd() }

    /// Adds a extra tag or attribute to the test suite, any number of tags can be reported
    /// - Parameters:
    ///   - key: The name of the tag, if a tag exists with the name it will be
    ///     replaced with the new value
    ///   - value: The value of the tag, can be a number or a string.
    @objc public func setTag(key: String, value: Any) {
        trySet(tag: key, value: value)
    }

    /// Starts a test in this suite
    /// - Parameters:
    ///   - name: name of the suite
    ///   - action: callback with test. Test will be ended automatically after call end
    @discardableResult
    @objc public func testStart(name: String, _ action: (DDTest) -> Any) -> Any {
        configuration.telemetry?.metrics.events.manualApiEvents.add(eventType: .test)
        return testStart(named: name, action)
    }

    /// Starts a test in this suite
    /// - Parameters:
    ///   - name: name of the suite
    ///   - startTime: start time for the test
    ///   - action: callback with test. Test will be ended automatically after call end
    @objc public func testStart(name: String, startTime: Date, _ action: (DDTest) -> Any) -> Any {
        configuration.telemetry?.metrics.events.manualApiEvents.add(eventType: .test)
        return testStart(named: name, at: startTime, action)
    }

    public func testStart<T>(named name: String, at start: Date? = nil,
                             _ action: (DDTest) throws -> T) rethrows -> T
    {
        try DDTest.withActiveTest(named: name, in: self, at: start, action)
    }

    public func testStart<T>(named name: String, at start: Date? = nil,
                             _ action: @Sendable (DDTest) async throws -> T) async rethrows -> T
    {
        try await DDTest.withActiveTest(named: name, in: self, at: start, action)
    }
}

extension DDSuite: TestSuite {
    var attributes: [String: TestAttributeValue] { span.getAttributes().testAttributes }

    func set(tag name: String, value: SpanAttributeConvertible) {
        span.setAttribute(key: name, value: .string(value.spanAttribute))
    }

    func set(metric name: String, value: Double) {
        span.setAttribute(key: name, value: .double(value))
    }

    func set(skipped reason: String? = nil) {
        if let reason = reason {
            set(tag: DDTestTags.testSkipReason, value: reason)
        }
        span.applyStatus(.skip, errorDescription: "")
    }

    func set(failed reason: TestError?) {
        var errorMessage = "Suite \(name) failed"
        if let error = reason {
            set(errorTags: error)
            errorMessage += ": \(error)"
        }
        span.applyStatus(.fail, errorDescription: errorMessage)
        module.set(failed: .init(type: "SuiteFailed", message: errorMessage))
    }

    func end(time: Date?) { end(endTime: time) }
}

extension DDSuite: TestRunProvider {
    func withActiveTest<T>(named name: String, _ action: @Sendable (any TestRun) async throws -> T) async rethrows -> T {
        try await testStart(named: name, action)
    }

    func withActiveTest<T>(named name: String, _ action: (any TestRun) throws -> T) rethrows -> T {
        try testStart(named: name, action)
    }
}
