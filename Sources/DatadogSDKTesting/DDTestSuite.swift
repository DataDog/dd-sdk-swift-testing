/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@preconcurrency internal import OpenTelemetryApi
internal import EventsExporter

@objc(DDTestSuite)
public final class Suite: NSObject {
    struct MutableState {
        var duration: UInt64 = 0
        var meta: [String: String] = [:]
        var metrics: [String: Double] = [:]
        var status: TestStatus = .pass
        var testsStarted: Int = 0
    }
    
    public let name: String
    public let startTime: Date
    public let testFramework: TestFramework
    public let localization: String
    
    var duration: UInt64 { _state.value.duration }
    var tags: [String: String] { _state.value.meta }
    var metrics: [String: Double] { _state.value.metrics }
    var status: TestStatus { _state.value.status }
    var configuration: SessionConfig { _module.configuration }
    
    let id: SpanId
    var module: TestModule { _module }
    
    private let _module: Module
    private let _state: Synced<MutableState>

    init(name: String, module: Module, framework: TestFramework, startTime: Date? = nil) {
        self.name = name
        self._module = module
        self.testFramework = framework
        self.localization = PlatformUtils.getLocalization()
        var state = MutableState()
        if let crash = module.configuration.crash?.suite, crash.name == name {
            state.status = .fail
            self.id = crash.id
            self.startTime = crash.startTime
        } else {
            self.id = SpanId.random()
            self.startTime = startTime ?? module.configuration.clock.now
        }
        
        state.meta[DDGenericTags.type] = DDTagValues.typeSuiteEnd
        state.meta[DDTestTags.testSuite] = name
        state.meta[DDTestTags.testModule] = module.name
        state.meta[DDTestTags.testFramework] = testFramework.name
        state.meta[DDTestTags.testFrameworkVersion] = testFramework.version
        state.meta[DDTestSuiteVisibilityTags.testSessionId] = String(module.session.id.rawValue)
        state.meta[DDTestSuiteVisibilityTags.testModuleId] = String(module.id.rawValue)
        state.meta[DDTestSuiteVisibilityTags.testSuiteId] = String(id.rawValue)
        state.meta[DDUISettingsTags.uiSettingsSuiteLocalization] = localization
        state.meta[DDUISettingsTags.uiSettingsModuleLocalization] = module.localization
            
        // Move to the global when we will support global metrics
        state.metrics.merge(module.configuration.metrics) { _, new in new }
        
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
        let duration = endTime.timeIntervalSince(startTime).toNanoseconds
        let snapshot: (meta: [String: String], metrics: [String: Double], status: TestStatus, shouldExport: Bool) =
            _state.update { state in
                state.duration = duration
                state.meta[DDTestTags.testStatus] = state.status.spanAttribute
                return (state.meta, state.metrics, state.status, state.testsStarted > 0)
            }
        // Don't emit a `test_suite_end` event for suites in which no tests
        // actually ran. This happens for container types that only enclose
        // nested @Suite types, and for XCTest's empty wrapper suites.
        guard snapshot.shouldExport else {
            Log.debug("Skipped suite_end event for empty suite \(name) (id: \(self.id))")
            return
        }

        var attributes: [String: AttributeValue] = ["resource": .string(name)]
        for (key, value) in snapshot.meta { attributes[key] = .string(value) }
        for (key, value) in snapshot.metrics { attributes[key] = .double(value) }

        let span = DDTestMonitor.tracer.createLifecycleSpan(name: "\(testFramework.name).suite",
                                                            spanId: id,
                                                            startTime: startTime,
                                                            attributes: attributes)
        if snapshot.status == .fail {
            span.status = .error(description: "suite failed")
        }
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
    @objc public func testStart(name: String, _ action: (Test) -> Any) -> Any {
        testStart(named: name, action)
    }
    
    /// Starts a test in this suite
    /// - Parameters:
    ///   - name: name of the suite
    ///   - startTime: start time for the test
    ///   - action: callback with test. Test will be ended automatically after call end
    @objc public func testStart(name: String, startTime: Date, _ action: (Test) -> Any) -> Any {
        testStart(named: name, at: startTime, action)
    }
    
    public func testStart<T>(named name: String, at start: Date? = nil,
                             _ action: (Test) throws -> T) rethrows -> T
    {
        try Test.withActiveTest(named: name, in: self, at: start, action)
    }
    
    public func testStart<T>(named name: String, at start: Date? = nil,
                             _ action: @Sendable (Test) async throws -> T) async rethrows -> T
    {
        try await Test.withActiveTest(named: name, in: self, at: start, action)
    }
}

extension Suite: TestSuite {
    func set(tag name: String, value: SpanAttributeConvertible) {
        _state.update {
            $0.meta[name] = value.spanAttribute
        }
    }
    
    func set(metric name: String, value: Double) {
        _state.update {
            $0.metrics[name] = value
        }
    }
    
    func set(skipped reason: String? = nil) {
        _state.update {
            $0.status = .skip
            if let reason = reason {
                $0.meta[DDTestTags.testSkipReason] = reason
            }
        }
    }
    
    func set(failed reason: TestError?) {
        _state.update {
            $0.status = .fail
        }
        var errorMessage = "Suite \(name) failed"
        if let error = reason {
            set(errorTags: error)
            errorMessage += ": \(error)"
        }
        module.set(failed: .init(type: "SuiteFailed", message: errorMessage))
    }
    
    func end(time: Date?) { end(endTime: time) }
}

extension Suite: TestRunProvider {    
    func withActiveTest<T>(named name: String, _ action: @Sendable (any TestRun) async throws -> T) async rethrows -> T {
        try await testStart(named: name, action)
    }
    
    func withActiveTest<T>(named name: String, _ action: (any TestRun) throws -> T) rethrows -> T {
        try testStart(named: name, action)
    }
}

