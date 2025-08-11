/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import OpenTelemetryApi

@objc(DDTestModule)
public final class Module: NSObject, Encodable {
    let name: String
    let session: TestSession
    let id: SpanId
    let startTime: Date
    var duration: UInt64
    var meta: [String: String] = [:]
    var metrics: [String: Double] = [:]
    var status: TestStatus
    var localization: String

    init(name: String, session: TestSession, startTime: Date?) {
        self.duration = 0
        self.status = .pass
        self.name = name
        self.session = session

        let moduleStartTime = startTime ?? DDTestMonitor.clock.now
        if let crashedModuleInfo = DDTestMonitor.instance?.crashedModuleInfo {
            self.status = .fail
            self.id = crashedModuleInfo.crashedModuleId
            self.startTime = crashedModuleInfo.moduleStartTime ?? moduleStartTime
        } else {
            self.id = SpanId.random()
            self.startTime = moduleStartTime
        }
        self.localization = PlatformUtils.getLocalization()
    }
    
    private func internalEnd(endTime: Date? = nil) {
        duration = (endTime ?? DDTestMonitor.clock.now).timeIntervalSince(startTime).toNanoseconds

        // If there is a Sanitizer message, we fail the module so error can be shown
        if let sanitizerInfo = SanitizerHelper.getSaniziterInfo() {
            self.set(failed: .init(type: "Sanitizer Error", stack: sanitizerInfo))
        }
        
        let moduleStatus = status.spanAttribute
        /// Export module event
        let moduleAttributes: [String: String] = [
            DDGenericTags.type: DDTagValues.typeModuleEnd,
            DDTestTags.testModule: name,
            DDTestTags.testFramework: session.testFramework,
            DDTestTags.testStatus: moduleStatus,
            DDTestSuiteVisibilityTags.testModuleId: String(id.rawValue),
            DDTestSuiteVisibilityTags.testSessionId: String(session.id.rawValue),
        ]
        meta.merge(moduleAttributes) { _, new in new }
        
        // Move to the global when we will support global metrics
        metrics.merge(DDTestMonitor.env.baseMetrics) { _, new in new }
        
        meta[DDUISettingsTags.uiSettingsModuleLocalization] = localization
        
        DDTestMonitor.tracer.eventsExporter?.exportEvent(event: ModuleEnvelope(self))
        Log.debug("Exported module_end event moduleId: \(self.id)")
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
        let suite = Suite(name: name, module: self, startTime: startTime)
        return suite
    }

    @objc func suiteStart(name: String) -> Suite {
        return suiteStart(name: name, startTime: nil)
    }
}

extension Module: TestModule {
    func set(tag name: String, value: SpanAttributeConvertible) {
        meta[name] = value.spanAttribute
    }
    
    func set(metric name: String, value: Double) {
        metrics[name] = value
    }
    
    func setSkipped() {
        status = .skip
    }
    
    func set(failed reason: TestError?) {
        status = .fail
        var errorMessage = "Module \(name) failed"
        if let error = reason {
            set(errorTags: error)
            errorMessage += ": \(error)"
        }
        session.set(failed: .init(type: "ModuleFailed", message: errorMessage))
    }
    
    func end(time: Date?) { end(endTime: time) }
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
        try container.encode(session.id.rawValue, forKey: .test_session_id)
        try container.encode(id.rawValue, forKey: .test_module_id)
        try container.encode(startTime.timeIntervalSince1970.toNanoseconds, forKey: .start)
        try container.encode(duration, forKey: .duration)
        try container.encode(meta, forKey: .meta)
        try container.encode(metrics, forKey: .metrics)
        try container.encode(status == .fail ? 1 : 0, forKey: .error)
        try container.encode("\(session.testFramework).module", forKey: .name)
        try container.encode(name, forKey: .resource)
        try container.encode(DDTestMonitor.env.service, forKey: .service)
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
