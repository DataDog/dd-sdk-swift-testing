/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
@testable import OpenTelemetrySdk
import XCTest

class StdoutCaptureTests: XCTestCase {
    private var originalTracer: DDTracer!

    override func setUp() {
        DDTestMonitor._env_recreate(env: ["DD_API_KEY": "fakeToken", "DD_DISABLE_TEST_INSTRUMENTING": "1"])
        originalTracer = DDTestMonitor.tracer
    }

    override func tearDown() {
        DDTestMonitor.tracer = originalTracer
        DDTestMonitor._env_recreate()
    }

    /// Install a DDTracer wired to an in-memory `LogRecordExporter` as
    /// the global `DDTestMonitor.tracer` (which `StdoutCapture` /
    /// `StderrCapture` route through) so the test can introspect what the SDK
    /// emitted.
    private func installCapturingTracer(_ exporter: InMemoryLogRecordExporter) -> DDTracer {
        let tracer = DDTracer(logRecordExporter: exporter)
        DDTestMonitor.tracer = tracer
        return tracer
    }

    func testWhenPrintIsCalledAndIsCapturing_stringIsForwardedAsLogRecord() {
        let logExporter = InMemoryLogRecordExporter()
        let tracer = installCapturingTracer(logExporter)
        let stringToCapture = "This should be captured"

        StdoutCapture.startCapturing()
        let spanData = tracer.withActiveSpan(name: "Unnamed", attributes: [:]) { span in
            print(stringToCapture)
            span.status = .ok
            return span.toSpanData()
        }
        StdoutCapture.stopCapturing()

        XCTAssertTrue(StdoutCapture.stdoutBuffer.isEmpty,
                      "buffer should be drained on newline")
        XCTAssertEqual(spanData.events.count, 0,
                       "stdout is now emitted as an OTel LogRecord, not as a span event")

        let records = logExporter.getFinishedLogRecords()
        XCTAssertEqual(records.count, 1)
        let record = records[0]
        XCTAssertEqual(record.body?.description, stringToCapture + "\n")
        XCTAssertEqual(record.severity, .info)
        XCTAssertEqual(record.spanContext?.spanId, spanData.spanId,
                       "log record must carry the active test span context")
        XCTAssertEqual(record.spanContext?.traceId, spanData.traceId)
    }

    func testWhenPrintIsCalledAndIsNotCapturing_stringIsNotForwarded() {
        let logExporter = InMemoryLogRecordExporter()
        let tracer = installCapturingTracer(logExporter)
        let stringToCapture = "This should be captured"

        StdoutCapture.startCapturing()
        StdoutCapture.stopCapturing()
        let spanData = tracer.withActiveSpan(name: "Unnamed", attributes: [:]) { span in
            print(stringToCapture)
            span.status = .ok
            return span.toSpanData()
        }
        XCTAssertTrue(StdoutCapture.stdoutBuffer.isEmpty)
        XCTAssertEqual(spanData.events.count, 0)
        XCTAssertEqual(logExporter.getFinishedLogRecords().count, 0)
    }

    func testWhenSomeCharactersAreWrittenToStdoutWithoutNewLines_charactersAreCapturedButNotForwarded() {
        let logExporter = InMemoryLogRecordExporter()
        let tracer = installCapturingTracer(logExporter)
        let stringToCapture = "This should  not be captured"

        StdoutCapture.startCapturing()
        let spanData = tracer.withActiveSpan(name: "Unnamed", attributes: [:]) { span in
            fputs(stringToCapture, stdout)
            let spanData = span.toSpanData()
            span.status = .ok
            return spanData
        }
        StdoutCapture.stopCapturing()

        XCTAssertFalse(StdoutCapture.stdoutBuffer.isEmpty)
        XCTAssertEqual(StdoutCapture.stdoutBuffer, stringToCapture)
        XCTAssertEqual(spanData.events.count, 0)
        XCTAssertEqual(logExporter.getFinishedLogRecords().count, 0,
                       "without a trailing newline the capture hook doesn't flush, so nothing reaches the logger")
    }
}
