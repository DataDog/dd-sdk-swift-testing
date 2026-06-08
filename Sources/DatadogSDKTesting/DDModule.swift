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
public final class DDModule: NSObject {
    struct MutableState {
        var testFrameworks: Set<String> = []
    }

    public let name: String
    public let localization: String

    public var testFrameworks: Set<String> { _state.value.testFrameworks }
    public var duration: UInt64 {
        span.endTime?.timeIntervalSince(span.startTime).toNanoseconds ?? 0
    }
    public var status: TestStatus { span.testStatus }

    var id: SpanId { span.context.spanId }
    let span: SpanSdk
    var session: TestSession { _session }
    var startTime: Date { span.startTime }

    private let _session: DDSession
    private let _state: Synced<MutableState>

    init(name: String, session: DDSession, startTime: Date?) {
        self.name = name
        self._session = session

        let state = MutableState()
        let id: SpanId
        let actualStartTime: Date
        let isCrashed: Bool
        if let crash = session.configuration.crash?.module, crash.name == name {
            isCrashed = true
            id = crash.id
            actualStartTime = crash.startTime
        } else {
            isCrashed = false
            id = SpanId.random()
            actualStartTime = startTime ?? session.configuration.clock.now
        }
        self.localization = PlatformUtils.getLocalization()

        var attributes: [String: AttributeValue] = [
            DDTestTags.testModule: .string(name),
            DDUISettingsTags.uiSettingsModuleLocalization: .string(localization),
        ]
        
        attributes.type = DDTagValues.typeModuleEnd
        attributes.resource = name
        attributes.testSessionId = session.id
        attributes.testModuleId = id
        
        for (key, value) in session.configuration.env.baseMetrics {
            attributes[key] = .double(value)
        }

        let span = DDTestMonitor.tracer.createLifecycleSpan(name: "Swift.module",
                                                            spanId: id,
                                                            startTime: actualStartTime,
                                                            attributes: attributes)
        if isCrashed {
            span.applyStatus(.fail, errorDescription: "module failed")
        }
        self.span = span

        self._state = .init(state)
        super.init()

        if let crash = session.configuration.crash?.module,
           let error = crash.error, crash.name == name
        {
            set(failed: error)
        }
    }

    private func internalEnd(endTime: Date? = nil) {
        let endTime = endTime ?? configuration.clock.now

        let framework = _state.use { state -> String in
            state.testFrameworks.count == 1
                ? "\(state.testFrameworks.first!).module"
                : "Swift.module"
        }

        span.setAttribute(key: DDTestTags.testFramework,
                          value: .string(_state.value.testFrameworks.joined(separator: ",")))
        span.name = framework
        // get-status -> set-status round-trip (see DDSession).
        span.applyStatus(span.testStatus, errorDescription: "module failed")
        span.end(time: endTime)

        configuration.log.debug("Exported module_end event moduleId: \(self.id)")
    }

    func addFramework(_ name: String) {
        let _ = _state.update { $0.testFrameworks.insert(name) }
        _session.addFramework(name)
    }
}

/// Public interface for DDModule
public extension DDModule {
    /// Ends the module
    /// - Parameters:
    ///   - endTime: Optional, the time where the module ended
    @objc(endWithTime:) func end(endTime: Date? = nil) {
        internalEnd(endTime: endTime)
    }

    @objc func end() {
        return end(endTime: nil)
    }

    /// Adds a extra tag or attribute to the test module, any number of tags can be reported
    /// - Parameters:
    ///   - key: The name of the tag, if a tag exists with the name it will be
    ///     replaced with the new value
    ///   - value: The value of the tag, can be a number or a string.
    @objc func setTag(key: String, value: Any) {
        trySet(tag: key, value: value)
    }

    /// Starts a suite in this module
    /// - Parameters:
    ///   - name: name of the suite
    ///   - startTime: Optional, the time where the suite started
    @objc func suiteStart(name: String, startTime: Date? = nil) -> DDSuite {
        configuration.telemetry?.metrics.events.manualApiEvents.add(eventType: .suite)
        return startSuite(named: name, at: startTime, framework: .init(name: "SwiftManual", version: "0.0.0")) as! DDSuite
    }

    @objc func suiteStart(name: String) -> DDSuite {
        return suiteStart(name: name, startTime: nil)
    }
}

extension DDModule: TestModule {
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
        var errorMessage = "Module \(name) failed"
        if let error = reason {
            set(errorTags: error)
            errorMessage += ": \(error)"
        }
        span.applyStatus(.fail, errorDescription: errorMessage)
        session.set(failed: .init(type: "ModuleFailed", message: errorMessage))
    }

    func end(time: Date?) { end(endTime: time) }
}

extension DDModule: TestSuiteProvider {
    func startSuite(named name: String, at start: Date?, framework: TestFramework) -> any TestRunProvider & TestSuite {
        addFramework(framework.name)
        return DDSuite(name: name, module: self, framework: framework, startTime: start)
    }
}
