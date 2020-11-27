/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import OpenTelemetrySdk

public struct NoopSpanProcessor: SpanProcessor {
    public let isStartRequired = false
    public let isEndRequired = false

    public func onStart(span: ReadableSpan) {
    }

    public func onEnd(span: ReadableSpan) {
    }

    public func shutdown() {
    }

    public func forceFlush() {
    }
}
