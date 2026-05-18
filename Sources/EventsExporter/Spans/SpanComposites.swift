/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

/// `SpanExporter` adapter that forwards each span's events to a
/// `LogsExporter` as log entries. Wrapped alongside the real `SpansExporter`
/// in an `OpenTelemetrySdk.MultiSpanExporter` so span events show up in the
/// logs pipeline without the caller having to register a separate
/// `LogRecordExporter`.
internal final class SpanEventsLogExporterAdapter: SpanExporter {
    private let logsExporter: LogsExporter

    init(logsExporter: LogsExporter) {
        self.logsExporter = logsExporter
    }

    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        spans.forEach { logsExporter.exportLogs(fromSpan: $0) }
        return .success
    }

    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        // Forwarding is fire-and-forget — the wrapped LogsExporter handles its
        // own flush via the EventsExporter facade.
        .success
    }

    func shutdown(explicitTimeout: TimeInterval?) {
        // Same — the LogsExporter is shut down directly via the EventsExporter.
    }
}
