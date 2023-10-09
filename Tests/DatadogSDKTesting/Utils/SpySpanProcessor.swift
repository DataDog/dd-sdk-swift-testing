/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi

import OpenTelemetrySdk

/// An implementation of the SpanProcessor that converts the ReadableSpan SpanData
///  and passes it to the configured exporter.
class SpySpanProcessor: SpanProcessor {
    var lastProcessedSpan: RecordEventsReadableSpan?

    init() {}

    let isStartRequired = false
    let isEndRequired = true

    func onStart(parentContext: SpanContext?, span: ReadableSpan) {}

    func onEnd(span: ReadableSpan) {
        lastProcessedSpan = span as? RecordEventsReadableSpan
    }

    func shutdown(explicitTimeout: TimeInterval?) {}

    func forceFlush(timeout: TimeInterval?) {}
}
