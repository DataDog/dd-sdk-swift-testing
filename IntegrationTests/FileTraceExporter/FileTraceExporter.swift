/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
@_implementationOnly import OpenTelemetrySdk

class FileTraceExporter: SpanExporter {
    private var outputURL: URL
    private var sampledSpans = [SimpleSpanData]()

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func export(spans: [SpanData]) -> SpanExporterResultCode {
        spans.forEach {
            let simpleSpan = SimpleSpanData(spanData: $0)
            sampledSpans.append(simpleSpan)
        }
        return .success
    }

    func flush() -> SpanExporterResultCode {
        do {
            let outputData = try JSONEncoder().encode(sampledSpans)
            try outputData.write(to: outputURL, options: .atomicWrite)
        } catch {
            return .failure
        }
        return .success
    }

    func reset() {}

    func shutdown() {}
}
