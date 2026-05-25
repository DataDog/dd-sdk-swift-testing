/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

/// `SpanExporter` adapter that turns each span's `SpanData.Event`s into
/// `ReadableLogRecord`s and forwards them to a `LogRecordExporter` (typically
/// the same `LogsExporter` that backs the EventsExporter facade). Wrapped
/// alongside the real `SpansExporter` in an
/// `OpenTelemetrySdk.MultiSpanExporter` so span events show up in the logs
/// pipeline without the caller having to register a separate
/// `LogRecordExporter`.
internal final class SpanEventsLogExporterAdapter: SpanExporter {
    private let logRecordExporter: LogRecordExporter

    init(logRecordExporter: LogRecordExporter) {
        self.logRecordExporter = logRecordExporter
    }

    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        var records: [ReadableLogRecord] = []
        for span in spans {
            for event in span.events {
                records.append(ReadableLogRecord(
                    resource: span.resource,
                    instrumentationScopeInfo: span.instrumentationScope,
                    timestamp: event.timestamp,
                    spanContext: SpanContext.create(
                        traceId: span.traceId,
                        spanId: span.spanId,
                        traceFlags: span.traceFlags,
                        traceState: span.traceState
                    ),
                    severity: Self.severity(from: event.attributes["status"]?.description),
                    body: nil,
                    attributes: event.attributes,
                    eventName: event.name
                ))
            }
        }
        guard !records.isEmpty else { return .success }
        return logRecordExporter.export(logRecords: records,
                                        explicitTimeout: explicitTimeout) == .success ? .success : .failure
    }

    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        // Forwarding is fire-and-forget — the wrapped log exporter handles its
        // own flush via the EventsExporter facade.
        .success
    }

    func shutdown(explicitTimeout: TimeInterval?) {
        // Same — the log exporter is shut down directly via the EventsExporter.
    }

    /// Map a `status` attribute (set by `DDTracer.logString` / `.logErrorString`)
    /// to an OTel `Severity` so `LogsExporter.export(logRecords:)` derives the
    /// right wire-level status.
    private static func severity(from status: String?) -> Severity? {
        switch status {
        case "debug": return .debug
        case "info": return .info
        case "notice": return .info2
        case "warn": return .warn
        case "error": return .error
        case "critical": return .fatal
        default: return nil
        }
    }
}
