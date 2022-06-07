/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

public class EventsExporter: SpanExporter {
    let configuration: ExporterConfiguration
    var spansExporter: SpansExporter
    var logsExporter: LogsExporter
    var coverageExporter: CoverageExporter

    public init(config: ExporterConfiguration) throws {
        self.configuration = config
        spansExporter = try SpansExporter(config: configuration)
        logsExporter = try LogsExporter(config: configuration)
        coverageExporter = try CoverageExporter(config: configuration)
    }

    public func export(spans: [SpanData]) -> SpanExporterResultCode {
        spans.forEach {
            if $0.traceFlags.sampled {
                spansExporter.exportSpan(span: $0)
            }
            if $0.traceFlags.sampled {
                logsExporter.exportLogs(fromSpan: $0)
            }
        }
        return .success
    }

    public func flush() -> SpanExporterResultCode {
        logsExporter.logsStorage.writer.queue.sync {}
        spansExporter.spansStorage.writer.queue.sync {}
        coverageExporter.coverageStorage.writer.queue.sync {}

        _ = logsExporter.logsUpload.uploader.flush()
        _ = spansExporter.spansUpload.uploader.flush()
        _ = coverageExporter.coverageUpload.uploader.flush()

        return .success
    }

    public func export(coverage: URL, traceId: String, spanId: String, binaryImagePaths: [String]) {
        coverageExporter.exportCoverage(coverage: coverage, traceId: traceId, spanId: spanId, binaryImagePaths: binaryImagePaths)
    }

    public func shutdown() {
        _ = self.flush()
    }

    public func endpointURLs() -> Set<String> {
        return [configuration.endpoint.logsURL.absoluteString,
                configuration.endpoint.spansURL.absoluteString,
                configuration.endpoint.coverageURL.absoluteString]
    }
}
