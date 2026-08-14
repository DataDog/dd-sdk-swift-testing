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
public final class DDSession: NSObject {
    struct MutableState {
        var testRunsCount: UInt = 0
        var testFrameworks: Set<String> = []
    }

    public let name: String
    public var testFrameworks: Set<String> { _state.value.testFrameworks }
    public var duration: UInt64 {
        span.endTime?.timeIntervalSince(span.startTime).toNanoseconds ?? 0
    }
    public var status: TestStatus { span.testStatus }

    var id: SpanId { span.context.spanId }
    let configuration: SessionConfig
    let span: SpanSdk
    var startTime: Date { span.startTime }
    var testRunsCount: UInt { _state.value.testRunsCount }

    private let _state: Synced<MutableState>
    private let _moduleManager: any TestModuleManagerSession
    /// Set only for sessions created through the manual `start(name:)` API, which
    /// owns its shutdown. Framework-driven sessions are owned by the
    /// `SessionManager` that created them, so it drives teardown instead.
    private let _sessionManager: (any TestSessionManager)?

    init(name: String, config: SessionConfig, modules: any TestModuleManagerSession,
         startTime: Date? = nil, sessionManager: (any TestSessionManager)? = nil) {
        self.name = name
        self.configuration = config
        self._moduleManager = modules
        self._sessionManager = sessionManager

        let state = MutableState()
        let id: SpanId
        let actualStartTime: Date
        let isCrashed: Bool
        if let crash = config.crash?.session {
            isCrashed = true
            id = crash.id
            actualStartTime = crash.startTime
        } else {
            isCrashed = false
            id = SpanId.random()
            actualStartTime = startTime ?? config.clock.now
        }

        var attributes: [String: AttributeValue] = [
            DDTestSessionTags.testToolchain: .string(config.env.platform.runtimeName.lowercased()
                                                     + "-" + config.env.platform.runtimeVersion),
        ]
        
        attributes.type = DDTagValues.typeSessionEnd
        attributes.resource = name
        attributes.testSessionId = id
        
        if let command = config.command {
            attributes[DDTestTags.testCommand] = .string(command)
        }
        for (key, value) in config.env.baseMetrics {
            attributes[key] = .double(value)
        }

        // Span name gets the framework-aware value at internalEnd; until then
        // we use a placeholder.
        let span = config.tracer.createLifecycleSpan(name: "Swift.session",
                                                     spanId: id,
                                                     startTime: actualStartTime,
                                                     attributes: attributes)
        if isCrashed {
            span.applyStatus(.fail, errorDescription: "session failed")
        }
        self.span = span
        self._state = .init(state)
    }

    private func internalEnd(endTime: Date? = nil) {
        let endTime = endTime ?? configuration.clock.now
        _moduleManager.stop()

        // If there is a Sanitizer message, we fail the session so error can be shown
        if let sanitizerInfo = SanitizerHelper.getSaniziterInfo() {
            self.set(failed: .init(type: "Sanitizer Error", stack: sanitizerInfo))
        }

        let framework = _state.use { state -> String in
            state.testFrameworks.count == 1
                ? "\(state.testFrameworks.first!).session"
                : "Swift.session"
        }

        span.setAttribute(key: DDTestTags.testFramework,
                          value: .string(_state.value.testFrameworks.joined(separator: ",")))
        span.name = framework
        // get-status -> set-status round-trip: writes the canonical
        // `test.status` tag (even if it was only visible through
        // `span.status` set by some other code path).
        span.applyStatus(span.testStatus, errorDescription: "session failed")
        span.end(time: endTime)

        configuration.log.debug("Exported session_end event sessionId: \(self.id)")
    }

    func addFramework(_ name: String) {
        let _ = _state.update { $0.testFrameworks.insert(name) }
    }
}

extension DDSession: TestSession {
    var attributes: [String: TestAttributeValue] { span.getAttributes().testAttributes }

    func set(tag name: String, value: any SpanAttributeConvertible) {
        span.setAttribute(key: name, value: .string(value.spanAttribute))
    }

    func set(metric name: String, value: Double) {
        span.setAttribute(key: name, value: .double(value))
    }

    func set(failed reason: TestError?) {
        if let error = reason {
            set(errorTags: error)
        }
        span.applyStatus(.fail, errorDescription: "session failed")
    }

    func set(skipped reason: String? = nil) {
        if let reason = reason {
            set(tag: DDTestTags.testSkipReason, value: reason)
        }
        span.applyStatus(.skip, errorDescription: "")
    }

    func nextTestIndex() -> UInt {
        _state.update { state in
            defer { state.testRunsCount += 1}
            return state.testRunsCount
        }
    }

    /// Ends the session's span only. The owning `SessionManager` calls this and
    /// then drives the rest of the shutdown itself, so this must not re-enter the
    /// manager the way the public `end` API does.
    func end(time: Date?) { internalEnd(endTime: time) }
}

/// Public interface for DDSession
public extension DDSession {
    /// Starts the test session
    ///
    /// Returns `nil` when the SDK can't run at all — most commonly a missing
    /// `DD_API_KEY`, without which nothing can be reported. There is no partially
    /// working session: check the result and skip your instrumentation if it's nil.
    /// - Parameters:
    ///   - name: name of the session
    ///   - command: Optional, test command that started this session
    ///   - startTime: Optional, the time where the session started
    @objc static func start(name: String, command: String? = nil, startTime: Date? = nil) -> DDSession? {
        // Bootstrap through a session manager, exactly like a framework-driven run
        // — so the session gets the same start hooks and the same shutdown path.
        // The manager is created first and handed to the session, which keeps it to
        // drive its own `end`.
        let manager = SessionManager(log: Log.instance,
                                     provider: DDSession.ManualProvider(),
                                     observer: SessionAndModuleObserver(),
                                     bootstrap: .manual(name: name, command: command,
                                                        startTime: startTime))
        // Blocking here is fine: this is session *start*, not the teardown path.
        guard let session = waitForAsync({ try? await manager.session }) as? DDSession else {
            Log.print("Could not start the test session: the test monitor is unavailable")
            return nil
        }
        // `session.started` / git-SHA telemetry is emitted by the session-start
        // feature hook (via the observer's `didStart`); only the manual-API counter
        // is specific to this entry point.
        session.configuration.telemetry?.metrics.events.manualApiEvents.add(eventType: .session)
        return session
    }

    @objc static func start(name: String) -> DDSession? {
        return start(name: name, command: nil)
    }

    /// Ends the session
    ///
    /// Shutdown (flushing and uploading everything gathered) runs through the
    /// session manager. This overload is fully synchronous and safe to call at
    /// process exit; prefer the `async` overload when you can await it.
    /// - Parameters:
    ///   - endTime: Optional, the time where the session ended
    @objc(endWithTime:) func end(endTime: Date? = nil) {
        internalEnd(endTime: endTime)
        _sessionManager?.stop()
    }

    @objc func end() {
        return end(endTime: nil)
    }

    /// Ends the session, awaiting the shutdown instead of blocking the caller.
    /// - Parameters:
    ///   - endTime: Optional, the time where the session ended
    func end(endTime: Date? = nil) async {
        internalEnd(endTime: endTime)
        await _sessionManager?.stop()
    }

    func end() async {
        await end(endTime: nil)
    }

    /// Adds a extra tag or attribute to the test session, any number of tags can be reported
    /// - Parameters:
    ///   - key: The name of the tag, if a tag exists with the name it will be
    ///     replaced with the new value
    ///   - value: The value of the tag, can be a number or a string.
    @objc func setTag(key: String, value: Any) {
        trySet(tag: key, value: value)
    }

    /// Starts a module in this session
    /// - Parameters:
    ///   - name: name of the module
    ///   - startTime: Optional, the time where the module started
    @objc func moduleStart(name: String, startTime: Date? = nil) -> DDModule {
        configuration.telemetry?.metrics.events.manualApiEvents.add(eventType: .module)
        return _moduleManager.module(named: name, at: startTime, provider: self) as! DDModule
    }

    @objc func moduleStart(name: String) -> DDModule {
        return moduleStart(name: name, startTime: nil)
    }
}

extension DDSession: TestModuleProvider {
    func startModule(named name: String, at start: Date?) -> any TestModule & TestSuiteProvider {
        DDModule(name: name, session: self, startTime: start)
    }
}

extension DDSession: TestModuleManager {
    func module(named name: String) -> any TestModule & TestSuiteProvider {
        moduleStart(name: name, startTime: configuration.clock.now)
    }

    func end(module: any TestModule) {
        _moduleManager.end(module: module, at: configuration.clock.now)
    }
}
