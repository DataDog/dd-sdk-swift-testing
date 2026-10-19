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
    var lastProcessedSpan: SpanSdk?

    private let lock = NSLock()
    private var _startedSpans: [ReadableSpan] = []
    private var _endedSpans: [ReadableSpan] = []

    /// Every span started since creation, including ones that never end.
    var startedSpans: [ReadableSpan] { lock.lock(); defer { lock.unlock() }; return _startedSpans }
    /// Every span ended since creation.
    var endedSpans: [ReadableSpan] { lock.lock(); defer { lock.unlock() }; return _endedSpans }

    init() {}

    let isStartRequired = true
    let isEndRequired = true

    func onStart(parentContext: SpanContext?, span: ReadableSpan) {
        lock.lock(); defer { lock.unlock() }
        _startedSpans.append(span)
    }

    func onEnd(span: ReadableSpan) {
        lock.lock()
        _endedSpans.append(span)
        lock.unlock()
        lastProcessedSpan = span as? SpanSdk
    }

    func shutdown(explicitTimeout: TimeInterval?) {}

    func forceFlush(timeout: TimeInterval?) {}
}
