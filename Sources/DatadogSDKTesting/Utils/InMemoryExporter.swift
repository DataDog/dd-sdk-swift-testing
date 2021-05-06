/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

public class OtelInMemoryExporter: SpanExporter {
    private var finishedSpanItems: [SpanData] = []
    private var isRunning: Bool = true

    public func getFinishedSpanItems() -> [SpanData] {
        return finishedSpanItems
    }

    public func export(spans: [SpanData]) -> SpanExporterResultCode {
        guard isRunning else {
            return .failure
        }

        finishedSpanItems.append(contentsOf: spans)
        return .success
    }

    public func flush() -> SpanExporterResultCode {
        guard isRunning else {
            return .failure
        }

        return .success
    }

    public func reset() {
        finishedSpanItems.removeAll()
    }

    public func shutdown() {
        finishedSpanItems.removeAll()
        isRunning = false
    }
}
