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
    public let resource: String
    public var testFrameworks: Set<String> { _state.value.testFrameworks }
    public var duration: UInt64 { _state.value.duration }
    public var meta: [String: String] { _state.value.meta }
    public var metrics: [String: Double] { _state.value.metrics }
    public var status: TestStatus { _state.value.status }
    
    let id: SpanId
    let configuration: SessionConfig
    var testRunsCount: UInt { _state.value.testRunsCount }
    
    private let _state: Synced<MutableState>
    private let _moduleManager: any TestModuleManagerSession
    
    init(name: String, config: SessionConfig, modules: any TestModuleManagerSession, startTime: Date? = nil) {
        self.name = name
        self.resource = name
        self.configuration = config
        self._moduleManager = modules
        
        var state = MutableState()
        state.meta[DDTestTags.testCommand] = config.command
        
        let sessionStartTime = startTime ?? config.clock.now
        if let crash = config.crash {
            state.status = .fail
            self.id = crash.crashedSessionId
            self.startTime = crash.sessionStartTime ?? sessionStartTime
        } else {
            self.id = SpanId.random()
            self.startTime = sessionStartTime
        }
        self._state = .init(state)
    }
    
    private func internalEnd(endTime: Date? = nil) {
        let duration = (endTime ?? configuration.clock.now).timeIntervalSince(startTime).toNanoseconds
        _state.update { state in
            state.duration = duration
            state.meta[DDGenericTags.type] = DDTagValues.typeSessionEnd
            state.meta[DDTestTags.testFramework] = state.testFrameworks.joined(separator: ",")
            state.meta[DDTestTags.testStatus] = state.status.spanAttribute
            state.meta[DDTestSuiteVisibilityTags.testSessionId] = String(id.rawValue)
            state.meta[DDTestSessionTags.testToolchain] = configuration.platform.runtimeName.lowercased() + "-" + configuration.platform.runtimeVersion
            
            // Move to the global when we will support global metrics
            state.metrics.merge(DDTestMonitor.env.baseMetrics) { _, new in new }
            
            addFeatureTags(meta: &state.meta, metrics: &state.metrics)
        }
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
                                   platform: DDTestMonitor.env.platform,
                                   clock: DDTestMonitor.clock,
                                   crash: nil,
                                   command: command,
                                   log: Log.instance)
        return Session(name: name, config: config, modules: Module.StatelessManager(), startTime: startTime)
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
    var moduleShouldEnd: Bool {
        _moduleManager.moduleShouldEnd
    }
    
    func module(named name: String) -> any TestModule & TestSuiteProvider {
        moduleStart(name: name)
    }
    
    func stopModules() {
        _moduleManager.stopModules()
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
        try container.encode(id.rawValue, forKey: .test_session_id)
        try container.encode(startTime.timeIntervalSince1970.toNanoseconds, forKey: .start)
        try container.encode(duration, forKey: .duration)
        try container.encode(meta, forKey: .meta)
        try container.encode(metrics, forKey: .metrics)
        try container.encode(status == .fail ? 1 : 0, forKey: .error)
        try container.encode(name, forKey: .name)
        try container.encode(resource, forKey: .resource)
        try container.encode(DDTestMonitor.env.service, forKey: .service)
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

protocol ModuleFeatureTagsHelper: AnyObject {
    var activeFeatures: [any TestHooksFeature] { get }
    func addFeatureTags(meta: inout [String: String], metrics: inout [String: Double])
}

extension Session: ModuleFeatureTagsHelper {
    var activeFeatures: [any TestHooksFeature] { configuration.activeFeatures }
}

extension ModuleFeatureTagsHelper {
    func addFeatureTags(meta: inout [String: String], metrics: inout [String: Double]) {
        var itrSkipped: UInt = 0
        
        if let tia = activeFeatures.first(where: { $0 is TestImpactAnalysis }) as? TestImpactAnalysis {
            meta[DDTestSessionTags.testCodeCoverageEnabled] = tia.isCoverageEnabled.spanAttribute
            meta[DDTestSessionTags.testSkippingEnabled] = tia.isSkippingEnabled.spanAttribute
            
            if tia.isSkippingEnabled {
                itrSkipped = tia.skippedCount
                meta[DDTestSessionTags.testItrSkippingType] = DDTagValues.typeTest
                meta[DDItrTags.itrSkippedTests] = (itrSkipped > 0).spanAttribute
                meta[DDTestSessionTags.testItrSkipped] = (itrSkipped > 0).spanAttribute
                metrics[DDTestSessionTags.testItrSkippingCount] = Double(itrSkipped)
            }
        }
        
        if activeFeatures.first(where: { $0 is TestManagement }) != nil {
            meta[DDTestSessionTags.testTestManagementEnabled] = "true"
        }
        
        if metrics[DDTestSessionTags.testCoverageLines] == nil,
           itrSkipped == 0,
           let linesCovered = DDCoverageHelper.getLineCodeCoverage()
        {
            metrics[DDTestSessionTags.testCoverageLines] = linesCovered
        }
        
        if let efd = activeFeatures.first(where: { $0 is EarlyFlakeDetection }) as? EarlyFlakeDetection {
            meta[DDEfdTags.testEfdEnabled] = "true"
            if efd.sessionFailed {
                meta[DDEfdTags.testEfdAbortReason] = DDTagValues.efdAbortFaulty
            }
        }
    }
}
