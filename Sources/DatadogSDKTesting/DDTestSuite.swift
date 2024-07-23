/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import OpenTelemetryApi

public class DDTestSuite: NSObject, Encodable {
    var name: String
    var module: DDTestModule
    var id: SpanId
    let startTime: Date
    var duration: UInt64
    var meta: [String: String] = [:]
    var status: DDTestStatus
    var unskippable: Bool = false
    var localization: String

    init(name: String, module: DDTestModule, startTime: Date? = nil) {
        self.name = name
        self.module = module
        self.startTime = DDTestMonitor.instance?.crashedModuleInfo?.suiteStartTime ?? startTime ?? DDTestMonitor.clock.now
        self.duration = 0
        self.status = .pass

        if DDTestMonitor.instance?.crashedModuleInfo?.crashedSuiteName == name {
            self.id = DDTestMonitor.instance?.crashedModuleInfo?.crashedSuiteId ?? SpanId.random()
            DDTestMonitor.instance?.crashedModuleInfo = nil
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
        duration = (endTime ?? DDTestMonitor.clock.now).timeIntervalSince(startTime).toNanoseconds
        /// Export module event

        let suiteStatus: String
        switch status {
            case .pass:
                suiteStatus = DDTagValues.statusPass
            case .fail:
                suiteStatus = DDTagValues.statusFail
            case .skip:
                suiteStatus = DDTagValues.statusSkip
        }

        let defaultAttributes: [String: String] = [
            DDTags.service: DDTestMonitor.config.service ?? DDTestMonitor.env.git.repositoryName ?? "unknown-swift-repo",
            DDGenericTags.type: DDTagValues.typeSuiteEnd,
            DDGenericTags.language: "swift",
            DDDeviceTags.deviceName: DDTestMonitor.env.platform.deviceName,
            DDTestTags.testSuite: name,
            DDTestTags.testFramework: module.testFramework,
            DDTestTags.testStatus: suiteStatus,
            DDTestSuiteVisibilityTags.testModuleId: String(module.id.rawValue),
            DDTestSuiteVisibilityTags.testSuiteId: String(id.rawValue)
        ]

        meta.merge(DDTestMonitor.baseConfigurationTags) { _, new in new }
        meta.merge(defaultAttributes) { _, new in new }
        meta.merge(DDTestMonitor.env.gitAttributes) { _, new in new }
        meta.merge(DDTestMonitor.env.ciAttributes) { _, new in new }
        meta[DDUISettingsTags.uiSettingsSuiteLocalization] = localization
        meta[DDUISettingsTags.uiSettingsModuleLocalization] = module.localization
        if unskippable { meta[DDItrTags.itrUnskippable] = "true" }
        
        DDTestMonitor.tracer.eventsExporter?.exportEvent(event: DDTestSuiteEnvelope(self))
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
    @objc public func setTag(key: String, value: Any) {}

    /// Starts a test in this suite
    /// - Parameters:
    ///   - name: name of the suite
    ///   - startTime: Optional, the time where the test started
    @objc public func testStart(name: String, startTime: Date? = nil) -> DDTest {
        return DDTest(name: name, suite: self, module: module, startTime: startTime)
    }

    @objc public func testStart(name: String) -> DDTest {
        return testStart(name: name, startTime: nil)
    }
}

extension DDTestSuite {
    enum StaticCodingKeys: String, CodingKey {
        case test_session_id
        case test_module_id
        case test_suite_id
        case start
        case duration
        case meta
        case error
        case name
        case resource
        case service
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StaticCodingKeys.self)
        try container.encode(module.sessionId.rawValue, forKey: .test_session_id)
        try container.encode(module.id.rawValue, forKey: .test_module_id)
        try container.encode(id.rawValue, forKey: .test_suite_id)
        try container.encode(startTime.timeIntervalSince1970.toNanoseconds, forKey: .start)
        try container.encode(duration, forKey: .duration)
        try container.encode(meta, forKey: .meta)
        try container.encode(status == .fail ? 1 : 0, forKey: .error)
        try container.encode("\(module.testFramework).suite", forKey: .name)
        try container.encode("\(name)", forKey: .resource)
        try container.encode(DDTestMonitor.config.service ?? DDTestMonitor.env.git.repositoryName ?? "unknown-swift-repo", forKey: .service)
    }

    struct DDTestSuiteEnvelope: Encodable {
        enum CodingKeys: String, CodingKey {
            case type
            case version
            case content
        }

        let version: Int = 1

        let type: String = DDTagValues.typeSuiteEnd
        let content: DDTestSuite

        init(_ content: DDTestSuite) {
            self.content = content
        }
    }
}
