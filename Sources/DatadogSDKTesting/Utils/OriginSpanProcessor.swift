/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */
import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

/// A span processor that decorates spans with the origin attribute
public struct OriginSpanProcessor: SpanProcessor {
    public let isStartRequired = true
    public let isEndRequired = false

    public func onStart(parentContext: SpanContext?, span: ReadableSpan) {
        span.setAttribute(key: DDGenericTags.origin, value: DDTagValues.originCiApp)
    }

    public mutating func onEnd(span: ReadableSpan) {}
    public func shutdown() {}
    public func forceFlush() {}
}
