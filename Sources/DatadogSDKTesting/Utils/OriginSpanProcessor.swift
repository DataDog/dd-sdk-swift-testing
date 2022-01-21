/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
@_implementationOnly import OpenTelemetryApi
@_implementationOnly import OpenTelemetrySdk

/// A span processor that decorates spans with the origin attribute
internal struct OriginSpanProcessor: SpanProcessor {
    let isStartRequired = true
    let isEndRequired = false

    func onStart(parentContext: SpanContext?, span: ReadableSpan) {
        span.setAttribute(key: DDGenericTags.origin, value: DDTagValues.originCiApp)
    }

    mutating func onEnd(span: ReadableSpan) {}
    func shutdown() {}
    func forceFlush(timeout: TimeInterval?) {}
}
