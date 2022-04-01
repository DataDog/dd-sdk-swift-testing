/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

public class OpenTelemetryExporter: SpanExporter {
    let configuration: ExporterConfiguration
    var spansExporter: SpansExporter?
    var logsExporter: LogsExporter?

    public init(config: ExporterConfiguration) throws {
        self.configuration = config
        spansExporter = try SpansExporter(config: configuration)
        logsExporter = try LogsExporter(config: configuration)
    }

    public func export(spans: [SpanData]) -> SpanExporterResultCode {
        spans.forEach {
            if $0.traceFlags.sampled {
                spansExporter?.exportSpan(span: $0)
            }
            if $0.traceFlags.sampled {
                logsExporter?.exportLogs(fromSpan: $0)
            }
        }
        return .success
    }

    public func flush() -> SpanExporterResultCode {
        spansExporter?.spansStorage.writer.queue.sync {}
        logsExporter?.logsStorage.writer.queue.sync {}

        _ = logsExporter?.logsUpload.uploader.flush()
        _ = spansExporter?.spansUpload.uploader.flush()
        return .success
    }

    public func shutdown() {
        _ = self.flush()
    }

    public func endpointURLs() -> Set<String> {
        return [configuration.endpoint.logsURL.absoluteString,
                configuration.endpoint.spansURL.absoluteString]
    }
}
