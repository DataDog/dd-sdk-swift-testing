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
    let id: SpanId
    let command: String
    let startTime: Date
    var duration: TimeInterval
    var attributes: [String: String] = [:]
    var status: String = "pass"

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
        self.id = SpanId.random()
        self.startTime = startTime ?? DDTestMonitor.clock.now
        self.command = bundleName
        self.duration = 0

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
    }

    func internalEnd(endTime: Date? = nil) {
        duration = (endTime ?? DDTestMonitor.clock.now).timeIntervalSince(startTime)
        /// Export session event
        attributes["env"] = DDTestMonitor.env.ddEnvironment ?? (DDTestMonitor.env.isCi ? "ci" : "none")
        attributes["test_session.status"] = status
        attributes.merge(DDEnvironmentValues.gitAttributes) { _, new in new }
        attributes.merge(DDEnvironmentValues.ciAttributes) { _, new in new }
        DDTestMonitor.tracer.opentelemetryExporter?.exportEvent(event: DDTestSessionEnvelope(content: self))
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
        case attributes
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StaticCodingKeys.self)
        try container.encode(id.rawValue, forKey: .test_session_id)
        try container.encode(startTime.timeIntervalSince1970, forKey: .start)
        try container.encode(duration, forKey: .duration)
        try container.encode(attributes, forKey: .attributes)
    }

    struct DDTestSessionEnvelope: Encodable {
        enum CodingKeys: String, CodingKey {
            case type
            case version
            case content
        }

        let version: Int = 1

        let type: String = "test_session_end"
        let content: DDTestSession

        init(content: DDTestSession) {
            self.content = content
        }
    }
}
