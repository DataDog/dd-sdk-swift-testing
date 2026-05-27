/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

public protocol ExporterProtocol: SpanExporter, LogRecordExporter, CoverageExporterType {
    var maxObjectSize: UInt64 { get }

    /// Rebuild the spans file header from the supplied `SpanMetadata` and
    /// rotate the writable file so the new header takes effect on the next
    /// batch.
    func setMetadata(_ metadata: SpanMetadata)
}

public final class Exporter: ExporterProtocol {
    let configuration: ExporterConfiguration
    let spansExporter: SpansExporter
    let logsExporter: LogsExporter
    let coverageExporter: CoverageExporter

    /// Composite that fans `SpanExporter.export(spans:)` out to both the spans
    /// pipeline and a `SpanEventsLogExporterAdapter` so span events end up in
    /// the logs pipeline transparently. Sampling-gated by the public facade.
    private let spanExporterComposite: SpanExporter

    public var maxObjectSize: UInt64 { configuration.performancePreset.maxObjectSize }

    public init(config: ExporterConfiguration,
                api: TestOptimizationApi,
                storage: Directory) throws
    {
        self.configuration = config
        Log.setLogger(config.logger)

        let spansExporter = try SpansExporter(config: configuration,
                                              storage: try storage.createSubdirectory(path: "spans"),
                                              api: api.spans)
        let logsExporter = try LogsExporter(config: configuration,
                                            storage: try storage.createSubdirectory(path: "logs"),
                                            api: api.logs)
        self.spansExporter = spansExporter
        self.logsExporter = logsExporter
        self.coverageExporter = try CoverageExporter(config: configuration,
                                                     storage: try storage.createSubdirectory(path: "coverage"),
                                                     api: api.tia)
        self.spanExporterComposite = OpenTelemetrySdk.MultiSpanExporter(spanExporters: [
            spansExporter,
            SpanEventsLogExporterAdapter(logRecordExporter: logsExporter),
        ])

        Log.debug("Exporter created: \(spansExporter.runtimeId)")
    }

    public func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        // TODO: Honor the timeout
        let sampled = spans.filter { $0.traceFlags.sampled }
        guard !sampled.isEmpty else { return .success }
        return spanExporterComposite.export(spans: sampled, explicitTimeout: explicitTimeout)
    }

    public func setMetadata(_ metadata: SpanMetadata) {
        spansExporter.setMetadata(metadata)
    }

    public func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        // TODO: Honor the timeout
        let logsOK = (try? logsExporter.logsStorage.flush()) ?? false
        let spansOK = (try? spansExporter.spansStorage.flush()) ?? false
        let covOK = (try? coverageExporter.coverageStorage.flush()) ?? false
        return (logsOK && spansOK && covOK) ? .success : .failure
    }

    @discardableResult
    public func export(coverageData: [CoverageData], explicitTimeout: TimeInterval?) -> ExportResult {
        coverageExporter.export(coverageData: coverageData, explicitTimeout: explicitTimeout)
    }

    public func shutdown(explicitTimeout: TimeInterval?) {
        _ = self.flush(explicitTimeout: explicitTimeout)
        logsExporter.shutdown()
        spansExporter.shutdown()
        coverageExporter.shutdown()
    }

    /// OTel `LogRecordExporter` conformance — forwarded to the wrapped
    /// `LogsExporter`. Lets a consumer register the `EventsExporter` as the
    /// `LogRecordExporter` on a `LoggerProviderSdk`, so logs emitted through
    /// `OpenTelemetry.instance.loggerProvider` flow into the same upload
    /// pipeline as span-event-derived logs. `shutdown(explicitTimeout:)` is
    /// already provided for the `SpanExporter` conformance and satisfies
    /// `LogRecordExporter`'s requirement of the same signature.
    public func export(logRecords: [ReadableLogRecord], explicitTimeout: TimeInterval?) -> ExportResult {
        logsExporter.export(logRecords: logRecords, explicitTimeout: explicitTimeout)
    }

    public func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult {
        logsExporter.forceFlush(explicitTimeout: explicitTimeout)
    }
}
