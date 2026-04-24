/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@preconcurrency internal import OpenTelemetryApi

@objc(DDTestModule)
public final class Module: NSObject, Encodable {
    struct MutableState {
        var duration: UInt64 = 0
        var meta: [String: String] = [:]
        var metrics: [String: Double] = [:]
        var status: TestStatus = .pass
        var testFrameworks: Set<String> = []
    }
    
    public let name: String
    public let startTime: Date
    public let localization: String
    
    public var testFrameworks: Set<String> { _state.value.testFrameworks }
    public var duration: UInt64 { _state.value.duration }
    public var tags: [String: String] { _state.value.meta }
    public var metrics: [String: Double] { _state.value.metrics }
    public var status: TestStatus { _state.value.status }
    
    let id: SpanId
    var session: TestSession { _session }
    var configuration: SessionConfig { _session.configuration }
    
    private let _session: Session
    private let _state: Synced<MutableState>

    init(name: String, session: Session, startTime: Date?) {
        self.name = name
        self._session = session

        var state = MutableState()
        let moduleStartTime = startTime ?? session.configuration.clock.now
        if let crash = session.configuration.crash?.module, crash.name == name {
            state.status = .fail
            self.id = crash.id
            self.startTime = crash.startTime
        } else {
            self.id = SpanId.random()
            self.startTime = moduleStartTime
        }
        self.localization = PlatformUtils.getLocalization()
        
        state.meta[DDGenericTags.type] = DDTagValues.typeModuleEnd
        state.meta[DDTestTags.testModule] = name
        state.meta[DDTestSuiteVisibilityTags.testModuleId] = String(id.rawValue)
        state.meta[DDTestSuiteVisibilityTags.testSessionId] = String(session.id.rawValue)
        state.meta[DDUISettingsTags.uiSettingsModuleLocalization] = localization
        
        // Move to the global when we will support global metrics
        state.metrics.merge(session.configuration.metrics) { _, new in new }
        
        self._state = .init(state)
        super.init()
        
        if let crash = session.configuration.crash?.module,
           let error = crash.error, crash.name == name
        {
            set(failed: error)
        }
    }
    
    private func internalEnd(endTime: Date? = nil) {
        let duration = (endTime ?? configuration.clock.now).timeIntervalSince(startTime).toNanoseconds
        _state.update { state in
            state.duration = duration
            state.meta[DDTestTags.testFramework] = state.testFrameworks.joined(separator: ",")
            state.meta[DDTestTags.testStatus] = state.status.spanAttribute
        }
        DDTestMonitor.tracer.eventsExporter?.exportEvent(event: ModuleEnvelope(self))
        configuration.log.debug("Exported module_end event moduleId: \(self.id)")
    }
    
    func addFramework(_ name: String) {
        let _ = _state.update { $0.testFrameworks.insert(name) }
        _session.addFramework(name)
    }
}

/// Public interface for DDTestModule
public extension Module {
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
    @objc func suiteStart(name: String, startTime: Date? = nil) -> Suite {
        startSuite(named: name, at: startTime, framework: .init(name: "SwiftManual", version: "0.0.0")) as! Suite
    }

    @objc func suiteStart(name: String) -> Suite {
        return suiteStart(name: name, startTime: nil)
    }
}

extension Module: TestModule {
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
        var errorMessage = "Module \(name) failed"
        if let error = reason {
            set(errorTags: error)
            errorMessage += ": \(error)"
        }
        session.set(failed: .init(type: "ModuleFailed", message: errorMessage))
    }
    
    func end(time: Date?) { end(endTime: time) }
}

extension Module: TestSuiteProvider {
    func startSuite(named name: String, at start: Date?, framework: TestFramework) -> any TestRunProvider & TestSuite {
        addFramework(framework.name)
        return Suite(name: name, module: self, framework: framework, startTime: start)
    }
}

extension Module {
    enum StaticCodingKeys: String, CodingKey {
        case test_session_id
        case test_module_id
        case start
        case duration
        case meta
        case metrics
        case error
        case name
        case resource
        case service
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StaticCodingKeys.self)
        try _state.use { state in
            try container.encode(session.id.rawValue, forKey: .test_session_id)
            try container.encode(id.rawValue, forKey: .test_module_id)
            try container.encode(startTime.timeIntervalSince1970.toNanoseconds, forKey: .start)
            try container.encode(state.duration, forKey: .duration)
            try container.encode(state.meta, forKey: .meta)
            try container.encode(state.metrics, forKey: .metrics)
            try container.encode(state.status == .fail ? 1 : 0, forKey: .error)
            if state.testFrameworks.count == 1, let framework = state.testFrameworks.first {
                try container.encode("\(framework).module", forKey: .name)
            } else {
                try container.encode("Swift.module", forKey: .name)
            }
            try container.encode(name, forKey: .resource)
            try container.encode(DDTestMonitor.env.service, forKey: .service)
        }
    }

    struct ModuleEnvelope: Encodable {
        enum CodingKeys: String, CodingKey {
            case type
            case version
            case content
        }

        let version: Int = 1

        let type: String = DDTagValues.typeModuleEnd
        let content: Module

        init(_ content: Module) {
            self.content = content
        }
    }
}
