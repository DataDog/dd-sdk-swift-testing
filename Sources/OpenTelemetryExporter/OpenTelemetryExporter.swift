/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
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
