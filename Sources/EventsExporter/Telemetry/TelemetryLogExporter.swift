/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

internal final class TelemetryLogExporter: LogRecordExporter {
    let telemetryExporter: TelemetryExporter

    init(telemetryExporter: TelemetryExporter) {
        self.telemetryExporter = telemetryExporter
    }

    func export(logRecords: [ReadableLogRecord], explicitTimeout: TimeInterval?) -> ExportResult {
        guard !logRecords.isEmpty else { return .success }
        telemetryExporter.export(item: TelemetryLog.Logs(logRecords.map(TelemetryLog.init(_:))))
        return .success
    }

    func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult {
        telemetryExporter.flush() ? .success : .failure
    }

    func shutdown(explicitTimeout: TimeInterval?) {
        telemetryExporter.shutdown()
    }
}

private extension TelemetryLog {
    init(_ record: ReadableLogRecord) {
        var attributes = record.attributes
        let message = record.body?.description
            ?? attributes.removeValue(forKey: "message")?.description
            ?? record.eventName
            ?? "Log event"
        let stackTrace = attributes.removeValue(forKey: "exception.stacktrace")?.description
        let tracerTime = Int64((record.observedTimestamp ?? record.timestamp).timeIntervalSince1970)
        let tags = attributes.isEmpty ? nil : attributes
            .map { "\($0.key):\($0.value.description)" }
            .sorted()
            .joined(separator: ",")

        self.init(
            message: message,
            level: TelemetryLog.Level(severity: record.severity),
            tags: tags,
            stackTrace: stackTrace,
            tracerTime: tracerTime
        )
    }
}

private extension TelemetryLog.Level {
    init(severity: Severity?) {
        switch severity {
        case .error, .error2, .error3, .error4,
             .fatal, .fatal2, .fatal3, .fatal4:
            self = .error
        case .warn, .warn2, .warn3, .warn4:
            self = .warn
        default:
            self = .debug
        }
    }
}
