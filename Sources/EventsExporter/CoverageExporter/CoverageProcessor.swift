/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

/// OTel-style processor for coverage records — analogous to
/// `SpanProcessor` / `LogRecordProcessor`. The SDK's
/// `CodeCoverageProvider` hands a per-test `CoverageRecord` (URL form)
/// to a processor when a test ends. The processor synchronously parses
/// the profraw, builds `CoverageData`, and forwards it to a
/// `CoverageExporterType`.
///
/// The concrete implementation (e.g. `SimpleCoverageProcessor` in the
/// SDK module) is the only place that needs to link a coverage parsing
/// library; this protocol keeps the `EventsExporter` module
/// parser-agnostic.
public protocol CoverageProcessor {
    /// Called when a coverage gathering session has produced a new record.
    func onEnd(record: CoverageRecord)

    /// Drain any queued coverage data to the exporter.
    @discardableResult
    func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult

    /// Stop scheduling work and shut the underlying exporter down.
    func shutdown(explicitTimeout: TimeInterval?)
}

public extension CoverageProcessor {
    @discardableResult
    func forceFlush() -> ExportResult { forceFlush(explicitTimeout: nil) }
    func shutdown() { shutdown(explicitTimeout: nil) }
}
