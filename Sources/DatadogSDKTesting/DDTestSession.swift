/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
@_implementationOnly import OpenTelemetryApi

@objc public enum DDTestStatus: Int {
    case pass
    case fail
    case skip
}

public class DDTestSession: NSObject, Encodable {
    var bundleName = ""
    var bundleFunctionInfo = FunctionMap()
    var codeOwners: CodeOwners?
    var testFramework = "Swift API"
    var id: SpanId
    let command: String
    let startTime: Date
    var duration: UInt64
    var meta: [String: String] = [:]
    var status: DDTestStatus
    var localization: String

    private let executionLock = NSLock()
    private var privateCurrentExecutionOrder = 0
    var currentExecutionOrder: Int {
        executionLock.lock()
        defer {
            privateCurrentExecutionOrder += 1
            executionLock.unlock()
        }
        return privateCurrentExecutionOrder
    }

    init(bundleName: String, startTime: Date?) {
        let sessionStartTime = startTime ?? DDTestMonitor.clock.now
        self.command = bundleName
        self.duration = 0
        self.status = .pass
        if DDTestMonitor.instance == nil {
            DDTestMonitor.installTestMonitor()
        }

        self.bundleName = bundleName
#if targetEnvironment(simulator) || os(macOS)
        DDSymbolicator.createDSYMFileIfNeeded(forImageName: bundleName)
        bundleFunctionInfo = FileLocator.testFunctionsInModule(bundleName)
#endif
        if let workspacePath = DDTestMonitor.env.workspacePath {
            codeOwners = CodeOwners(workspacePath: URL(fileURLWithPath: workspacePath))
        }

        if !DDTestMonitor.env.disableCrashHandler {
            DDCrashes.install()
        }
        self.id = DDTestMonitor.instance?.crashedSessionInfo?.crashedSessionId ?? SpanId.random()
        self.startTime = DDTestMonitor.instance?.crashedSessionInfo?.sessionStartTime ?? sessionStartTime
        self.localization = PlatformUtils.getLocalization()
    }

    func internalEnd(endTime: Date? = nil) {
        duration = (endTime ?? DDTestMonitor.clock.now).timeIntervalSince(startTime).toNanoseconds

        let suiteStatus: String
        switch status {
            case .pass:
                suiteStatus = DDTagValues.statusPass
            case .fail:
                suiteStatus = DDTagValues.statusFail
            case .skip:
                suiteStatus = DDTagValues.statusSkip
        }

        /// Export session event
        let defaultAttributes: [String: String] = [
            DDGenericTags.type: DDTagValues.typeSuiteEnd,
            DDGenericTags.language: "swift",
            DDTestTags.testSuite: bundleName,
            DDTestTags.testFramework: testFramework,
            DDTestTags.testBundle: bundleName,
            DDTestTags.testStatus: suiteStatus,
            DDOSTags.osPlatform: DDTestMonitor.env.osName,
            DDOSTags.osArchitecture: DDTestMonitor.env.osArchitecture,
            DDOSTags.osVersion: DDTestMonitor.env.osVersion,
            DDDeviceTags.deviceName: DDTestMonitor.env.deviceName,
            DDDeviceTags.deviceModel: DDTestMonitor.env.deviceModel,
            DDRuntimeTags.runtimeName: DDTestMonitor.env.runtimeName,
            DDRuntimeTags.runtimeVersion: DDTestMonitor.env.runtimeVersion,
            DDTestSessionTags.testSessionId: String(id.rawValue)
        ]
        meta.merge(defaultAttributes) { _, new in new }
        meta.merge(DDEnvironmentValues.gitAttributes) { _, new in new }
        meta.merge(DDEnvironmentValues.ciAttributes) { _, new in new }
        meta[DDUISettingsTags.uiSettingsSessionLocalization] = localization
        DDTestMonitor.tracer.opentelemetryExporter?.exportEvent(event: DDTestSessionEnvelope(self))
        /// We need to wait for all the traces to be written to the backend before exiting
        DDTestMonitor.tracer.flush()
    }
}

/// Public interface for DDTestSession
public extension DDTestSession {
    /// Starts the session
    /// - Parameters:
    ///   - bundleName: name of the module or bundle to test.
    ///   - startTime: Optional, the time where the session started
    @objc static func start(bundleName: String, startTime: Date? = nil) -> DDTestSession {
        let session = DDTestSession(bundleName: bundleName, startTime: startTime)
        return session
    }

    @objc static func start(bundleName: String) -> DDTestSession {
        return start(bundleName: bundleName, startTime: nil)
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
    @objc func setTag(key: String, value: Any) {}

    /// Starts a suite in this session
    /// - Parameters:
    ///   - name: name of the suite
    ///   - startTime: Optional, the time where the suite started
    @objc func suiteStart(name: String, startTime: Date? = nil) -> DDTestSuite {
        let suite = DDTestSuite(name: name, session: self, startTime: startTime)
        return suite
    }

    @objc func suiteStart(name: String) -> DDTestSuite {
        return suiteStart(name: name, startTime: nil)
    }
}

extension DDTestSession {
    enum StaticCodingKeys: String, CodingKey {
        case test_session_id
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
        try container.encode(id.rawValue, forKey: .test_session_id)
        try container.encode(startTime.timeIntervalSince1970.toNanoseconds, forKey: .start)
        try container.encode(duration, forKey: .duration)
        try container.encode(meta, forKey: .meta)
        try container.encode(status == .fail ? 1 : 0, forKey: .error)
        try container.encode("\(testFramework).session", forKey: .name)
        try container.encode("\(bundleName)", forKey: .resource)
        try container.encode(DDTestMonitor.env.ddService ?? DDTestMonitor.env.getRepositoryName() ?? "unknown-swift-repo", forKey: .service)
    }

    struct DDTestSessionEnvelope: Encodable {
        enum CodingKeys: String, CodingKey {
            case type
            case version
            case content
        }

        let version: Int = 1

        let type: String = DDTagValues.typeSessionEnd
        let content: DDTestSession

        init(_ content: DDTestSession) {
            self.content = content
        }
    }
}
