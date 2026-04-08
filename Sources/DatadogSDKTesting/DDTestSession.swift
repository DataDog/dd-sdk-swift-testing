/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@preconcurrency internal import OpenTelemetryApi

@objc(DDTestSession)
public final class Session: NSObject, Encodable {
    struct MutableState {
        var duration: UInt64 = 0
        var meta: [String: String] = [:]
        var metrics: [String: Double] = [:]
        var status: TestStatus = .pass
        var testRunsCount: UInt = 0
        var testFrameworks: Set<String> = []
    }
    
    public let name: String
    public let startTime: Date
    public var testFrameworks: Set<String> { _state.value.testFrameworks }
    public var duration: UInt64 { _state.value.duration }
    public var tags: [String: String] { _state.value.meta }
    public var metrics: [String: Double] { _state.value.metrics }
    public var status: TestStatus { _state.value.status }
    
    let id: SpanId
    let configuration: SessionConfig
    var testRunsCount: UInt { _state.value.testRunsCount }
    
    private let _state: Synced<MutableState>
    private let _moduleManager: any TestModuleManagerSession
    
    init(name: String, config: SessionConfig, modules: any TestModuleManagerSession, startTime: Date? = nil) {
        self.name = name
        self.configuration = config
        self._moduleManager = modules
        
        var state = MutableState()
        state.meta[DDTestTags.testCommand] = config.command
        
        let sessionStartTime = startTime ?? config.clock.now
        if let crash = config.crash?.session {
            state.status = .fail
            self.id = crash.id
            self.startTime = crash.startTime
        } else {
            self.id = SpanId.random()
            self.startTime = sessionStartTime
        }
        
        state.meta[DDGenericTags.type] = DDTagValues.typeSessionEnd
        state.meta[DDTestSuiteVisibilityTags.testSessionId] = String(id.rawValue)
        state.meta[DDTestSessionTags.testToolchain] = configuration.platform.runtimeName.lowercased() + "-" + configuration.platform.runtimeVersion
        
        // Move to the global when we will support global metrics
        state.metrics.merge(configuration.metrics) { _, new in new }
        
        self._state = .init(state)
    }
    
    private func internalEnd(endTime: Date? = nil) {
        let duration = (endTime ?? configuration.clock.now).timeIntervalSince(startTime).toNanoseconds
        _moduleManager.stop()
        
        // If there is a Sanitizer message, we fail the session so error can be shown
        if let sanitizerInfo = SanitizerHelper.getSaniziterInfo() {
            self.set(failed: .init(type: "Sanitizer Error", stack: sanitizerInfo))
        }
        
        // Update meta tags to the latest state
        _state.update { state in
            state.duration = duration
            state.meta[DDTestTags.testFramework] = state.testFrameworks.joined(separator: ",")
            state.meta[DDTestTags.testStatus] = state.status.spanAttribute
        }
        // export it
        DDTestMonitor.tracer.eventsExporter?.exportEvent(event: SessionEnvelope(self))
        configuration.log.debug("Exported session_end event sessionId: \(self.id)")
        DDTestMonitor.tracer.flush()
    }
    
    func addFramework(_ name: String) {
        let _ = _state.update { $0.testFrameworks.insert(name) }
    }
}

extension Session: TestSession {
    func set(tag name: String, value: any SpanAttributeConvertible) {
        _state.update {
            $0.meta[name] = value.spanAttribute
        }
    }
    
    func set(metric name: String, value: Double) {
        _state.update {
            $0.metrics[name] = value
        }
    }
    
    func set(failed reason: TestError?) {
        _state.update {
            $0.status = .fail
        }
        if let error = reason {
            set(errorTags: error)
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
    
    func nextTestIndex() -> UInt {
        _state.update { state in
            defer { state.testRunsCount += 1}
            return state.testRunsCount
        }
    }
    
    func end(time: Date?) { end(endTime: time) }
}

/// Public interface for Session
public extension Session {
    /// Starts the test session
    /// - Parameters:
    ///   - name: name of the session
    ///   - command: Optional, test command that started this session
    ///   - startTime: Optional, the time where the session started
    @objc static func start(name: String, command: String? = nil, startTime: Date? = nil) -> Session {
        let config = SessionConfig(activeFeatures: [],
                                   workspacePath: DDTestMonitor.env.workspacePath,
                                   codeOwners: DDTestMonitor.instance?.codeOwners,
                                   bundleFunctions: DDTestMonitor.instance?.bundleFunctionInfo ?? .init(),
                                   platform: DDTestMonitor.env.platform,
                                   clock: DDTestMonitor.clock,
                                   crash: DDTestMonitor.instance?.crashInfo,
                                   command: command,
                                   service: DDTestMonitor.env.service,
                                   metrics: DDTestMonitor.env.baseMetrics,
                                   log: Log.instance)
        waitForAsync {
            do {
                try await DDTestMonitor.clock.sync()
            } catch {
                DDTestMonitor.clock = DateClock()
            }
        }
        return Session(name: name, config: config,
                       modules: Module.StatelessManager(config: config,
                                                        observer: SessionAndModuleObserver()),
                       startTime: startTime)
    }

    @objc static func start(name: String) -> Session {
        return start(name: name, command: nil)
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
    @objc func setTag(key: String, value: Any) {
        trySet(tag: key, value: value)
    }

    /// Starts a module in this session
    /// - Parameters:
    ///   - name: name of the module
    ///   - startTime: Optional, the time where the module started
    @objc func moduleStart(name: String, startTime: Date? = nil) -> Module {
        return _moduleManager.module(named: name, at: startTime, provider: self) as! Module
    }

    @objc func moduleStart(name: String) -> Module {
        return moduleStart(name: name, startTime: nil)
    }
}

extension Session: TestModuleProvider {
    func startModule(named name: String, at start: Date?) -> any TestModule & TestSuiteProvider {
        Module(name: name, session: self, startTime: start)
    }
}

extension Session: TestModuleManager {
    func module(named name: String) -> any TestModule & TestSuiteProvider {
        moduleStart(name: name, startTime: configuration.clock.now)
    }
    
    func end(module: any TestModule) {
        _moduleManager.end(module: module, at: configuration.clock.now)
    }
}

extension Session {
    enum StaticCodingKeys: String, CodingKey {
        case test_session_id
        case name
        case resource
        case error
        case meta
        case metrics
        case start
        case duration
        case service
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StaticCodingKeys.self)
        try _state.use { state in
            try container.encode(id.rawValue, forKey: .test_session_id)
            try container.encode(startTime.timeIntervalSince1970.toNanoseconds, forKey: .start)
            try container.encode(state.duration, forKey: .duration)
            try container.encode(state.meta, forKey: .meta)
            try container.encode(state.metrics, forKey: .metrics)
            try container.encode(state.status == .fail ? 1 : 0, forKey: .error)
            if state.testFrameworks.count == 1, let framework = state.testFrameworks.first {
                try container.encode("\(framework).session", forKey: .name)
            } else {
                try container.encode("Swift.session", forKey: .name)
            }
            try container.encode(name, forKey: .resource)
            try container.encode(configuration.service, forKey: .service)
        }
    }

    struct SessionEnvelope: Encodable {
        enum CodingKeys: String, CodingKey {
            case type
            case version
            case content
        }

        let version: Int = 1

        let type: String = DDTagValues.typeSessionEnd
        let content: Session

        init(_ content: Session) {
            self.content = content
        }
    }
}

