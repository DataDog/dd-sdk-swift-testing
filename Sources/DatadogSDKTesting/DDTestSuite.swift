/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter
internal import OpenTelemetryApi

@objc(DDTestSuite)
public final class Suite: NSObject, Encodable {
    let name: String
    let module: TestModule
    let id: SpanId
    let startTime: Date
    var duration: UInt64
    var meta: [String: String] = [:]
    var metrics: [String: Double] = [:]
    var status: TestStatus
    var localization: String

    init(name: String, module: TestModule, startTime: Date? = nil) {
        self.name = name
        self.module = module
        self.startTime = DDTestMonitor.instance?.crashedModuleInfo?.suiteStartTime ?? startTime ?? DDTestMonitor.clock.now
        self.duration = 0
        self.status = .pass

        if DDTestMonitor.instance?.crashedModuleInfo?.crashedSuiteName == name {
            self.id = DDTestMonitor.instance?.crashedModuleInfo?.crashedSuiteId ?? SpanId.random()
            DDTestMonitor.instance?.crashedModuleInfo = nil
            self.status = .fail
        } else {
            self.id = SpanId.random()
        }
        self.localization = PlatformUtils.getLocalization()

        // If we are recovering from a crash, clean the crash information
        if DDTestMonitor.instance?.crashedModuleInfo != nil {
            DDTestMonitor.instance?.crashedModuleInfo = nil
        }
    }

    private func internalEnd(endTime: Date? = nil) {
        duration = (endTime ?? DDTestMonitor.clock.now).timeIntervalSince(startTime).toNanosecondsUInt
        /// Export module event

        let suiteAttributes: [String: String] = [
            DDGenericTags.type: DDTagValues.typeSuiteEnd,
            DDTestTags.testSuite: name,
            DDTestTags.testModule: module.name,
            DDTestTags.testFramework: module.session.testFramework,
            DDTestTags.testStatus: status.spanAttribute,
            DDTestSuiteVisibilityTags.testSessionId: String(session.id.rawValue),
            DDTestSuiteVisibilityTags.testModuleId: String(module.id.rawValue),
            DDTestSuiteVisibilityTags.testSuiteId: String(id.rawValue)
        ]
        meta.merge(suiteAttributes) { _, new in new }
        
        // Move to the global when we will support global metrics
        metrics.merge(DDTestMonitor.env.baseMetrics) { _, new in new }
        
        meta[DDUISettingsTags.uiSettingsSuiteLocalization] = localization
        meta[DDUISettingsTags.uiSettingsModuleLocalization] = module.localization
        
        DDTestMonitor.tracer.eventsExporter?.exportEvent(event: SuiteEnvelope(self))
        Log.debug("Exported suite_end event suiteId: \(self.id)")
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
    ///   - startTime: Optional, the time where the test started
    @objc public func testStart(name: String, startTime: Date? = nil) -> Test {
        Test(name: name, suite: self, startTime: startTime)
    }

    @objc public func testStart(name: String) -> Test {
        testStart(name: name, startTime: nil)
    }
}

extension Suite: TestSuite {
    func set(tag name: String, value: SpanAttributeConvertible) {
        meta[name] = value.spanAttribute
    }
    
    func set(metric name: String, value: Double) {
        metrics[name] = value
    }
    
    func set(skipped reason: String? = nil) {
        status = .skip
        if let reason = reason {
            meta[DDTestTags.testSkipReason] = reason
        }
    }
    
    func set(failed reason: TestError?) {
        status = .fail
        var errorMessage = "Suite \(name) failed"
        if let error = reason {
            set(errorTags: error)
            errorMessage += ": \(error)"
        }
        module.set(failed: .init(type: "SuiteFailed", message: errorMessage))
    }
    
    func end(time: Date?) { end(endTime: time) }
}

extension Suite {
    enum StaticCodingKeys: String, CodingKey {
        case test_session_id
        case test_module_id
        case test_suite_id
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
        try container.encode(module.id.rawValue, forKey: .test_module_id)
        try container.encode(id.rawValue, forKey: .test_suite_id)
        try container.encode(startTime.timeIntervalSince1970.toNanoseconds, forKey: .start)
        try container.encode(duration, forKey: .duration)
        try container.encode(meta, forKey: .meta)
        try container.encode(metrics, forKey: .metrics)
        try container.encode(status == .fail ? 1 : 0, forKey: .error)
        try container.encode("\(session.testFramework).suite", forKey: .name)
        try container.encode("\(name)", forKey: .resource)
        try container.encode(DDTestMonitor.env.service, forKey: .service)
    }

    struct SuiteEnvelope: Encodable {
        enum CodingKeys: String, CodingKey {
            case type
            case version
            case content
        }

        let version: Int = 1

        let type: String = DDTagValues.typeSuiteEnd
        let content: Suite

        init(_ content: Suite) {
            self.content = content
        }
    }
}
