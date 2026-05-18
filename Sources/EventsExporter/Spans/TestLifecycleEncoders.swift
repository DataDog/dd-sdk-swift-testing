/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

// MARK: - Envelopes

internal struct TestSessionEnvelope: Encodable {
    enum CodingKeys: String, CodingKey {
        case spanType = "type"
        case version
        case content
    }

    let version: Int = 1
    let spanType: String = "test_session_end"
    let content: DDTestSessionSpan

    init(_ content: DDTestSessionSpan) {
        self.content = content
    }
}

internal struct TestModuleEnvelope: Encodable {
    enum CodingKeys: String, CodingKey {
        case spanType = "type"
        case version
        case content
    }

    let version: Int = 1
    let spanType: String = "test_module_end"
    let content: DDTestModuleSpan

    init(_ content: DDTestModuleSpan) {
        self.content = content
    }
}

internal struct TestSuiteEnvelope: Encodable {
    enum CodingKeys: String, CodingKey {
        case spanType = "type"
        case version
        case content
    }

    let version: Int = 1
    let spanType: String = "test_suite_end"
    let content: DDTestSuiteSpan

    init(_ content: DDTestSuiteSpan) {
        self.content = content
    }
}

// MARK: - SpanData-driven content

/// Fields the wire payload carries identically for sessions / modules / suites.
private struct CommonLifecycleFields {
    let start: UInt64
    let duration: UInt64
    let error: Int
    let name: String
    let resource: String
    let service: String
    let meta: [String: String]
    let metrics: [String: Double]

    /// Keys that are surfaced as their own top-level wire fields rather than
    /// inside `meta`. They stay in `meta` too (today's bytes preserve the
    /// duplication), so the filter list here is only for keys that the
    /// envelope's content doesn't carry at all (like the dispatch `type`
    /// attribute, which never appears in the legacy meta dictionary either —
    /// it's pre-seeded into `state.meta` and so it does end up in meta on the
    /// wire; we therefore do NOT filter it out).
    init(spanData: SpanData) {
        self.start = spanData.startTime.timeIntervalSince1970.toNanoseconds
        self.duration = spanData.endTime.timeIntervalSince(spanData.startTime).toNanoseconds
        switch spanData.status {
        case .error: self.error = 1
        default: self.error = 0
        }
        self.name = spanData.name
        self.resource = spanData.attributes[CommonLifecycleFields.resourceKey]?.description ?? spanData.name
        self.service = spanData.resource.service ?? ""

        var meta: [String: String] = [:]
        var metrics: [String: Double] = [:]
        for (key, value) in spanData.attributes {
            switch value {
            case .string(let s): meta[key] = s
            case .bool(let b): meta[key] = b ? "true" : "false"
            case .int(let i): metrics[key] = Double(i)
            case .double(let d): metrics[key] = d
            default: continue
            }
        }
        // `resource` is a distinct field on the wire, not part of meta.
        meta.removeValue(forKey: CommonLifecycleFields.resourceKey)
        self.meta = meta
        self.metrics = metrics
    }

    static let resourceKey = "resource"
}

internal struct DDTestSessionSpan: Encodable {
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

    private let testSessionId: UInt64
    private let common: CommonLifecycleFields

    init(spanData: SpanData) {
        self.testSessionId = spanData.spanId.rawValue
        self.common = CommonLifecycleFields(spanData: spanData)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: StaticCodingKeys.self)
        try c.encode(testSessionId, forKey: .test_session_id)
        try c.encode(common.start, forKey: .start)
        try c.encode(common.duration, forKey: .duration)
        try c.encode(common.meta, forKey: .meta)
        try c.encode(common.metrics, forKey: .metrics)
        try c.encode(common.error, forKey: .error)
        try c.encode(common.name, forKey: .name)
        try c.encode(common.resource, forKey: .resource)
        try c.encode(common.service, forKey: .service)
    }
}

internal struct DDTestModuleSpan: Encodable {
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

    private let testSessionId: UInt64
    private let testModuleId: UInt64
    private let common: CommonLifecycleFields

    init(spanData: SpanData) {
        self.testSessionId = UInt64(spanData.attributes["test_session_id"]?.description ?? "0") ?? 0
        self.testModuleId = spanData.spanId.rawValue
        self.common = CommonLifecycleFields(spanData: spanData)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: StaticCodingKeys.self)
        try c.encode(testSessionId, forKey: .test_session_id)
        try c.encode(testModuleId, forKey: .test_module_id)
        try c.encode(common.start, forKey: .start)
        try c.encode(common.duration, forKey: .duration)
        try c.encode(common.meta, forKey: .meta)
        try c.encode(common.metrics, forKey: .metrics)
        try c.encode(common.error, forKey: .error)
        try c.encode(common.name, forKey: .name)
        try c.encode(common.resource, forKey: .resource)
        try c.encode(common.service, forKey: .service)
    }
}

internal struct DDTestSuiteSpan: Encodable {
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

    private let testSessionId: UInt64
    private let testModuleId: UInt64
    private let testSuiteId: UInt64
    private let common: CommonLifecycleFields

    init(spanData: SpanData) {
        self.testSessionId = UInt64(spanData.attributes["test_session_id"]?.description ?? "0") ?? 0
        self.testModuleId = UInt64(spanData.attributes["test_module_id"]?.description ?? "0") ?? 0
        self.testSuiteId = spanData.spanId.rawValue
        self.common = CommonLifecycleFields(spanData: spanData)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: StaticCodingKeys.self)
        try c.encode(testSessionId, forKey: .test_session_id)
        try c.encode(testModuleId, forKey: .test_module_id)
        try c.encode(testSuiteId, forKey: .test_suite_id)
        try c.encode(common.start, forKey: .start)
        try c.encode(common.duration, forKey: .duration)
        try c.encode(common.meta, forKey: .meta)
        try c.encode(common.metrics, forKey: .metrics)
        try c.encode(common.error, forKey: .error)
        try c.encode(common.name, forKey: .name)
        try c.encode(common.resource, forKey: .resource)
        try c.encode(common.service, forKey: .service)
    }
}
