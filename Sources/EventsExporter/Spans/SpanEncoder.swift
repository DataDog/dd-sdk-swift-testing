/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

internal enum Constants {
    static let ddsource = "ios"
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

/// `Encodable` representation of a generic (non-test, non-lifecycle) span.
/// Test/session/module/suite spans are encoded via `TestSpan` instead.
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

    // MARK: - Meta

    let applicationVersion: String

    /// Custom tags, received from user
    var tags: [String: AttributeValue]

    static let filteredTagKeys: Set<String> = [
        "error.message", "error.type", "error.stack",
        "resource", "type", "version"
    ]

    func encode(to encoder: Encoder) throws {
        let sanitizedSpan = SpanSanitizer().sanitize(span: self)
        try SpanEncoder().encode(sanitizedSpan, to: encoder)
    }

    internal init(spanData: SpanData) {
        self.traceID = spanData.traceId
        self.spanID = spanData.spanId
        self.parentID = spanData.parentSpanId

        if spanData.attributes.type != nil {
            self.name = spanData.name
        } else {
            self.name = spanData.name + "." + spanData.kind.rawValue
        }

        self.serviceName = spanData.resource.service ?? ""
        self.resource = spanData.attributes.resource ?? spanData.name
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

        let spanType = spanData.attributes.type ?? spanData.attributes["db.type"]?.description
        self.type = spanType ?? spanData.kind.rawValue

        self.applicationVersion = spanData.resource.applicationVersion ?? ""
        self.tags = spanData.attributes.filter {
            !DDSpan.filteredTagKeys.contains($0.key)
        }
    }
}

/// Encodes `SpanData` to given encoder.
internal struct SpanEncoder {
    /// Coding keys for `Span` attributes.
    struct CodingKeys: CodingKey, ExpressibleByStringLiteral {
        typealias StringLiteralType = String
        let stringValue: String
        
        init?(stringValue: String) {
            self.stringValue = stringValue
        }
        
        init(stringLiteral value: String) {
            stringValue = value
        }
        
        init(_ string: String) {
            self.init(stringLiteral: string)
        }
        
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
        
        static var traceID: Self { "trace_id" }
        static var spanID: Self { "span_id" }
        static var parentID: Self { "parent_id" }
        static var name: Self { "name" }
        static var service: Self { "service" }
        static var resource: Self { "resource" }
        static var type: Self { "type" }
        static var start: Self { "start" }
        static var duration: Self { "duration" }
        static var error: Self { "error" }
        static var errorMessage: Self { "error.message" }
        static var errorType: Self { "error.type" }
        static var errorStack: Self { "error.stack" }

        // MARK: - Metrics

        static var isRootSpan: Self { "_top_level" }

        // MARK: - Meta

        static var source: Self { "_dd.source" }
        static var applicationVersion: Self { "version" }

        static var meta: Self { "meta" }
        static var metrics: Self { "metrics" }
    }

    func encode(_ span: DDSpan, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(span.traceID.rawLowerLong, forKey: .traceID)
        try container.encode(span.spanID.rawValue, forKey: .spanID)
        let parentSpanID = span.parentID ?? SpanId.invalid // 0 is a reserved ID for a root span (ref: DDTracer.java#L600)
        try container.encode(parentSpanID.rawValue, forKey: .parentID)

        try container.encode(span.name, forKey: .name)
        try container.encode(span.serviceName, forKey: .service)
        try container.encode(span.resource, forKey: .resource)
        try container.encode(span.type, forKey: .type)

        try container.encode(span.startTime, forKey: .start)
        try container.encode(span.duration, forKey: .duration)

        var meta = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .meta)
        var metrics = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .metrics)

        if span.error {
            try container.encode(1, forKey: .error)
            try meta.encodeIfPresent(span.errorMessage.map(truncateMetaStringValue), forKey: .errorMessage)
            try meta.encodeIfPresent(span.errorType.map(truncateMetaStringValue), forKey: .errorType)
            try meta.encodeIfPresent(span.errorStack.map(truncateMetaStringValue), forKey: .errorStack)
        } else {
            try container.encode(0, forKey: .error)
        }

        try encodeDefaultMetrics(span, to: &metrics)
        try encodeDefaultMeta(span, to: &meta)
        try encodeCustomAttributes(span, toMeta: &meta, metrics: &metrics)
    }

    /// Encodes default `metrics.*` attributes
    private func encodeDefaultMetrics(_ span: DDSpan, to metrics: inout KeyedEncodingContainer<CodingKeys>) throws {
        // NOTE: RUMM-299 only numeric values are supported for `metrics.*` attributes
        if span.parentID == nil {
            try metrics.encode(1, forKey: .isRootSpan)
        }
    }

    /// Encodes default `meta.*` attributes
    private func encodeDefaultMeta(_ span: DDSpan, to meta: inout KeyedEncodingContainer<CodingKeys>) throws {
        // NOTE: RUMM-299 only string values are supported for `meta.*` attributes
        try meta.encode(truncateMetaStringValue(Constants.ddsource), forKey: .source)
        try meta.encode(truncateMetaStringValue(span.applicationVersion), forKey: .applicationVersion)
    }

    /// Encodes `meta.*` attributes coming from user
    private func encodeCustomAttributes(_ span: DDSpan,
                                        toMeta meta: inout KeyedEncodingContainer<CodingKeys>,
                                        metrics: inout KeyedEncodingContainer<CodingKeys>) throws
    {
        // NOTE: RUMM-299 only string values are supported for `meta.*` attributes
        try span.tags.forEach {
            switch $0.value {
            case .int(let intValue):
                try metrics.encode(intValue, forKey: CodingKeys($0.key))
            case .double(let doubleValue):
                try metrics.encode(doubleValue, forKey: CodingKeys($0.key))
            default:
                try meta.encode(truncateMetaStringValue($0.value.description), forKey: CodingKeys($0.key))
            }
        }
    }
}
