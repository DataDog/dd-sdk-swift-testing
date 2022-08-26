/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

internal enum Constants {
    static let ddsource = "ios"
}

internal struct CITestEnvelope: Encodable {
    enum CodingKeys: String, CodingKey {
        case spanType = "type"
        case version
        case content
    }

    let version: Int = 2

    let spanType: String
    let content: DDSpan

    /// The initializer to encode single `Span` within an envelope.
    init(_ content: DDSpan) {
        self.spanType = "test"
        self.content = content
    }
}

internal struct SpanEnvelope: Encodable {
    enum CodingKeys: String, CodingKey {
        case spanType = "type"
        case version
        case content
    }

    let version: Int = 1

    let spanType: String
    let content: DDSpan

    /// The initializer to encode single `Span` within an envelope.
    init(_ content: DDSpan) {
        self.spanType = "span"
        self.content = content
    }
}

/// `Encodable` representation of span.
internal struct DDSpan: Encodable {
    let traceID: TraceId
    let spanID: SpanId
    let parentID: SpanId?
    let name: String
    let serviceName: String
    let resource: String
    let startTime: UInt64
    let duration: UInt64
    let error: Bool
    let errorMessage: String?
    let errorType: String?
    let errorStack: String?
    let type: String
    let moduleID: UInt64?
    let suiteID: UInt64?

    // MARK: - Meta

    let applicationVersion: String

    /// Custom tags, received from user
    var tags: [String: AttributeValue]

    static let filteredTagKeys: Set<String> = [
        "error.message", "error.type", "error.stack", "test_module_id", "test_suite_id"
    ]

    func encode(to encoder: Encoder) throws {
        let sanitizedSpan = SpanSanitizer().sanitize(span: self)
        try SpanEncoder().encode(sanitizedSpan, to: encoder)
    }

    internal init(spanData: SpanData, serviceName: String, applicationVersion: String) {
        self.traceID = spanData.traceId
        self.spanID = spanData.spanId
        self.parentID = spanData.parentSpanId

        if spanData.attributes["type"] != nil {
            self.name = spanData.name
        } else {
            self.name = spanData.name + "." + spanData.kind.rawValue
        }

        self.serviceName = serviceName
        self.resource = spanData.attributes["resource"]?.description ?? spanData.name
        self.startTime = spanData.startTime.timeIntervalSince1970.toNanoseconds
        self.duration = spanData.endTime.timeIntervalSince(spanData.startTime).toNanoseconds

        switch spanData.status {
            case .error(let errorDescription):
                self.error = true
                self.errorType = spanData.attributes["error.type"]?.description ?? errorDescription
                self.errorMessage = spanData.attributes["error.message"]?.description
                self.errorStack = spanData.attributes["error.stack"]?.description
            default:
                self.error = false
                self.errorMessage = nil
                self.errorType = nil
                self.errorStack = nil
        }

        let spanType = spanData.attributes["type"] ?? spanData.attributes["db.type"]
        self.type = spanType?.description ?? spanData.kind.rawValue

        if self.type == "test" {
            self.moduleID = UInt64(spanData.attributes["test_module_id"]?.description ?? "0", radix: 16) ?? 0
            self.suiteID = UInt64(spanData.attributes["test_suite_id"]?.description ?? "0", radix: 16) ?? 0
        } else {
            self.moduleID = nil
            self.suiteID = nil
        }

        self.applicationVersion = applicationVersion
        self.tags = spanData.attributes.filter {
            !DDSpan.filteredTagKeys.contains($0.key)
        }.mapValues { $0 }
    }
}

/// Encodes `SpanData` to given encoder.
internal struct SpanEncoder {
    /// Coding keys for permanent `Span` attributes.
    enum StaticCodingKeys: String, CodingKey {
        // MARK: - Attributes

        case traceID = "trace_id"
        case spanID = "span_id"
        case parentID = "parent_id"
        case testModuleID = "test_module_id"
        case testSuiteID = "test_suite_id"
        case name
        case service
        case resource
        case type
        case start
        case duration
        case error
        case errorMessage = "error.message"
        case errorType = "error.type"
        case errorStack = "error.stack"

        // MARK: - Metrics

        case isRootSpan = "_top_level"

        // MARK: - Meta

        case source = "_dd.source"
        case applicationVersion = "version"

        case meta
        case metrics
    }

    /// Coding keys for dynamic `Span` attributes specified by user.
    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        init(_ string: String) { self.stringValue = string }
    }

    func encode(_ span: DDSpan, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StaticCodingKeys.self)

        try container.encode(span.traceID.rawLowerLong, forKey: .traceID)
        try container.encode(span.spanID.rawValue, forKey: .spanID)
        let parentSpanID = span.parentID ?? SpanId.invalid // 0 is a reserved ID for a root span (ref: DDTracer.java#L600)
        try container.encode(parentSpanID.rawValue, forKey: .parentID)

        try container.encode(span.moduleID, forKey: .testModuleID)
        try container.encode(span.suiteID, forKey: .testSuiteID)

        try container.encode(span.name, forKey: .name)
        try container.encode(span.serviceName, forKey: .service)
        try container.encode(span.resource, forKey: .resource)
        try container.encode(span.type, forKey: .type)

        try container.encode(span.startTime, forKey: .start)
        try container.encode(span.duration, forKey: .duration)

        var meta = container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .meta)
        var metrics = container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .metrics)

        if span.error {
            try container.encode(1, forKey: .error)
            try meta.encode(span.errorMessage, forKey: DynamicCodingKey(StaticCodingKeys.errorMessage.stringValue))
            try meta.encode(span.errorType, forKey: DynamicCodingKey(StaticCodingKeys.errorType.stringValue))
            try meta.encode(span.errorStack, forKey: DynamicCodingKey(StaticCodingKeys.errorStack.stringValue))
        } else {
            try container.encode(0, forKey: .error)
        }

        try encodeDefaultMetrics(span, to: &metrics)
        try encodeDefaultMeta(span, to: &meta)
        try encodeCustomAttributes(span, toMeta: &meta, metrics: &metrics)
    }

    /// Encodes default `metrics.*` attributes
    private func encodeDefaultMetrics(_ span: DDSpan, to metrics: inout KeyedEncodingContainer<DynamicCodingKey>) throws {
        // NOTE: RUMM-299 only numeric values are supported for `metrics.*` attributes
        if span.parentID == nil {
            try metrics.encode(1, forKey: DynamicCodingKey(StaticCodingKeys.isRootSpan.stringValue))
        }
    }

    /// Encodes default `meta.*` attributes
    private func encodeDefaultMeta(_ span: DDSpan, to meta: inout KeyedEncodingContainer<DynamicCodingKey>) throws {
        // NOTE: RUMM-299 only string values are supported for `meta.*` attributes
        try meta.encode(Constants.ddsource, forKey: DynamicCodingKey(StaticCodingKeys.source.stringValue))
        try meta.encode(span.applicationVersion, forKey: DynamicCodingKey(StaticCodingKeys.applicationVersion.stringValue))
    }

    /// Encodes `meta.*` attributes coming from user
    private func encodeCustomAttributes(_ span: DDSpan,
                                        toMeta meta: inout KeyedEncodingContainer<DynamicCodingKey>,
                                        metrics: inout KeyedEncodingContainer<DynamicCodingKey>) throws
    {
        // NOTE: RUMM-299 only string values are supported for `meta.*` attributes
        try span.tags.forEach {
            switch $0.value {
                case .int(let intValue):
                    try metrics.encode(intValue, forKey: DynamicCodingKey($0.key))
                case .double(let doubleValue):
                    try metrics.encode(doubleValue, forKey: DynamicCodingKey($0.key))
                case .string(let stringValue):
                    try meta.encode(stringValue, forKey: DynamicCodingKey($0.key))
                case .bool(let boolValue):
                    try meta.encode(boolValue, forKey: DynamicCodingKey($0.key))
                default:
                    break
            }
        }
    }
}
