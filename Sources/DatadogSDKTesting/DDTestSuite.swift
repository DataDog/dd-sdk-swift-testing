/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
@_implementationOnly import OpenTelemetryApi

public class DDTestSuite: NSObject, Encodable {
    var name: String
    var session: DDTestSession
    let id: SpanId
    let startTime: Date
    var duration: TimeInterval
    var attributes: [String: String] = [:]
    var status: String = "pass"

    init(name: String, session: DDTestSession, startTime: Date? = nil) {
        self.name = name
        self.session = session
        self.id = SpanId()
        self.startTime = startTime ?? DDTestMonitor.clock.now
        self.duration = 0
    }

    func internalEnd(endTime: Date? = nil) {
        duration = (endTime ?? DDTestMonitor.clock.now).timeIntervalSince(startTime)
        /// Export session event
        attributes["env"] = DDTestMonitor.env.ddEnvironment ?? (DDTestMonitor.env.isCi ? "ci" : "none")
        attributes["suite.status"] = status
        attributes.merge(DDEnvironmentValues.gitAttributes) { _, new in new }
        attributes.merge(DDEnvironmentValues.ciAttributes) { _, new in new }
        DDTestMonitor.tracer.opentelemetryExporter?.exportEvent(event: DDTestSuiteEnvelope(content: self))
        /// We need to wait for all the traces to be written to the backend before exiting
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
        return DDTest(name: name, suite: self, session: session, startTime: startTime)
    }

    @objc public func testStart(name: String) -> DDTest {
        return testStart(name: name, startTime: nil)
    }
}

extension DDTestSuite {
    enum StaticCodingKeys: String, CodingKey {
        case test_session_id
        case test_suite_id
        case start
        case duration
        case attributes
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StaticCodingKeys.self)
        try container.encode(session.id.rawValue, forKey: .test_session_id)
        try container.encode(id.rawValue, forKey: .test_suite_id)
        try container.encode(startTime.timeIntervalSince1970, forKey: .start)
        try container.encode(duration, forKey: .duration)
        try container.encode(attributes, forKey: .attributes)
    }

    struct DDTestSuiteEnvelope: Encodable {
        enum CodingKeys: String, CodingKey {
            case type
            case version
            case content
        }

        let version: Int = 1

        let type: String = "test_suite_end"
        let content: DDTestSuite

        init(content: DDTestSuite) {
            self.content = content
        }
    }
}
