/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

/// Implementation of the SpanProcessor that simply forwards all received events to a list of
/// SpanProcessors.
struct MultiSpanProcessor: SpanProcessor {
    var spanProcessorsStart = [SpanProcessor]()
    var spanProcessorsEnd = [SpanProcessor]()
    var spanProcessorsAll = [SpanProcessor]()

    init(spanProcessors: [SpanProcessor]) {
        spanProcessorsAll = spanProcessors
        spanProcessorsAll.forEach {
            if $0.isStartRequired {
                spanProcessorsStart.append($0)
            }
            if $0.isEndRequired {
                spanProcessorsEnd.append($0)
            }
        }
    }

    var isStartRequired: Bool {
        return spanProcessorsStart.count > 0
    }

    var isEndRequired: Bool {
        return spanProcessorsEnd.count > 0
    }

    func onStart(parentContext: SpanContext?, span: ReadableSpan) {
        spanProcessorsStart.forEach {
            $0.onStart(parentContext: parentContext, span: span)
        }
    }

    func onEnd(span: ReadableSpan) {
        for var processor in spanProcessorsEnd {
            processor.onEnd(span: span)
        }
    }

    func shutdown() {
        for var processor in spanProcessorsAll {
            processor.shutdown()
        }
    }

    func forceFlush() {
        spanProcessorsAll.forEach {
            $0.forceFlush()
        }
    }
}
