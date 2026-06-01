/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

// MARK: - Envelope

struct TestSpanEnvelope: Encodable {
    enum CodingKeys: String, CodingKey {
        case spanType = "type"
        case version
        case content
    }

    let version: Int
    let spanType: String
    let content: TestSpan

    init(_ content: TestSpan) {
        self.spanType = content.spanType.rawValue
        self.content = content

        switch content.spanType {
        case .test: self.version = 2
        default: self.version = 1
        }
    }
}

// MARK: - Span

/// Wire-shape encoder for `test_session_end` / `test_module_end` /
/// `test_suite_end` / `test` events. The lifecycle and test wire formats
/// share most fields (session/module/suite IDs, name/resource/service,
/// start/duration/error, meta/metrics); the `.test` case layers on the
/// extra fields the backend needs to correlate a test span with its
/// trace (trace_id / span_id / parent_id), its dispatch `type`, an ITR
/// correlation id, and the legacy default meta (`_dd.source`, `version`)
/// and metrics (`_top_level` for root spans).
struct TestSpan: Encodable {
    enum SpanType: String, Encodable {
        case sessionEnd = "test_session_end"
        case moduleEnd = "test_module_end"
        case suiteEnd = "test_suite_end"
        case test
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case traceId = "trace_id"
        case spanId = "span_id"
        case parentId = "parent_id"
        case testSessionId = "test_session_id"
        case testModuleId = "test_module_id"
        case testSuiteId = "test_suite_id"
        case itrCorrelationId = "itr_correlation_id"
        case name
        case resource
        case service
        case type
        case start
        case duration
        case error
        case meta
        case metrics
    }

    /// Shared fields
    let start: UInt64
    let duration: UInt64
    let error: Int
    let name: String
    let resource: String
    let service: String
    let meta: [String: String]
    let metrics: [String: Double]
    
    let additional: AdditionalFields
    
    var spanType: SpanType {
        switch additional {
        case .sessionEnd: return .sessionEnd
        case .moduleEnd: return .moduleEnd
        case .suiteEnd: return .suiteEnd
        case .test: return .test
        }
    }

    init(spanData: SpanData, spanType: SpanType) {
        self.start = spanData.startTime.timeIntervalSince1970.toNanoseconds
        self.duration = spanData.endTime.timeIntervalSince(spanData.startTime).toNanoseconds

        let errorDescription: String?
        switch spanData.status {
        case .error(let desc):
            self.error = 1
            errorDescription = desc
        default:
            self.error = 0
            errorDescription = nil
        }

        self.name = spanData.name
        self.resource = spanData.attributes.resource ?? spanData.name
        self.service = spanData.resource.service ?? ""

        // Sanitize attribute keys (escape over-deep dot paths) and trim
        // over-long string values before splitting into meta/metrics.
        let filtered = spanData.attributes.filter { !Self.filteredKeys.contains($0.key) }
        let sanitizer = AttributesSanitizer(featureName: "TestSpan")
        let sanitized = sanitizer.sanitizeValues(for: sanitizer.sanitizeKeys(for: filtered))
        
        var meta = sanitized.meta
        var metrics = sanitized.metrics
        
        // Set error type if it was empty
        if self.error > 0, meta["error.type"] == nil {
            meta["error.type"] = errorDescription
        }

        switch spanType {
        case .sessionEnd:
            self.additional = .sessionEnd(sessionId: spanData.spanId.rawValue)
        case .moduleEnd:
            self.additional = .moduleEnd(sessionId: spanData.attributes.testSessionId?.rawValue ?? 0,
                                         moduleId: spanData.spanId.rawValue)
        case .suiteEnd:
            self.additional = .suiteEnd(sessionId: spanData.attributes.testSessionId?.rawValue ?? 0,
                                        moduleId: spanData.attributes.testModuleId?.rawValue ?? 0,
                                        suiteId: spanData.spanId.rawValue)
        case .test:
            // 0 is the reserved id for a root span.
            let parent = spanData.parentSpanId ?? .invalid
            self.additional = .test(
                sessionId: spanData.attributes.testSessionId?.rawValue ?? 0,
                moduleId: spanData.attributes.testModuleId?.rawValue ?? 0,
                suiteId: spanData.attributes.testSuiteId?.rawValue ?? 0,
                traceId: spanData.traceId.rawLowerLong,
                spanId: spanData.spanId.rawValue,
                parentId: parent.rawValue,
                itrCorrelationId: spanData.attributes.itrCorrelationId)
            if parent == .invalid {
                metrics[Self.topLevelKey] = 1
            }
            meta["_dd.source"] = Constants.ddsource
            if let version = spanData.resource.applicationVersion {
                meta["version"] = version
            }
        }

        self.meta = meta
        self.metrics = metrics
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(start, forKey: .start)
        try c.encode(duration, forKey: .duration)
        try c.encode(error, forKey: .error)
        try c.encode(name, forKey: .name)
        try c.encode(resource, forKey: .resource)
        try c.encode(service, forKey: .service)
        try c.encode(spanType.rawValue, forKey: .type)
        try c.encode(meta, forKey: .meta)
        try c.encode(metrics, forKey: .metrics)
        try additional.encode(in: &c)
    }

    static let topLevelKey = "_top_level"
    
    /// Attribute keys that the wire payload already carries as their own
    /// top-level fields. Stripping them from `meta` / `metrics` avoids
    /// duplicating the same data through a different shape.
    static let filteredKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue } +
                                               ["type", Self.topLevelKey])
}


extension TestSpan {
    enum AdditionalFields {
        case sessionEnd(sessionId: UInt64)
        case moduleEnd(sessionId: UInt64,
                       moduleId: UInt64)
        case suiteEnd(sessionId: UInt64,
                      moduleId: UInt64,
                      suiteId: UInt64)
        case test(sessionId: UInt64,
                  moduleId: UInt64,
                  suiteId: UInt64,
                  traceId: UInt64,
                  spanId: UInt64,
                  parentId: UInt64,
                  itrCorrelationId: String?)
        
        func encode(in coder: inout KeyedEncodingContainer<CodingKeys>) throws {
            switch self {
            case .test(let sessionId, let moduleId, let suiteId,
                       let traceId, let spanId, let parentId, let itrCorrelationId):
                try coder.encode(traceId, forKey: .traceId)
                try coder.encode(spanId, forKey: .spanId)
                try coder.encode(parentId, forKey: .parentId)
                try coder.encodeIfPresent(itrCorrelationId, forKey: .itrCorrelationId)
                fallthrough
            case .suiteEnd(let sessionId, let moduleId, let suiteId):
                try coder.encode(suiteId, forKey: .testSuiteId)
                fallthrough
            case .moduleEnd(let sessionId, let moduleId):
                try coder.encode(moduleId, forKey: .testModuleId)
                fallthrough
            case .sessionEnd(let sessionId):
                try coder.encode(sessionId, forKey: .testSessionId)
            }
        }
    }
}

extension Dictionary where Key == String, Value == AttributeValue {
    var metrics: [String: Double] {
        compactMapValues { value in
            switch value {
            case .double(let d): return d
            case .int(let i): return Double(i)
            default: return nil
            }
        }
    }

    var meta: [String: String] {
        compactMapValues { value in
            switch value {
            case .int, .double: return nil
            default: return value.description
            }
        }
    }
}
