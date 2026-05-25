/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
@testable import OpenTelemetrySdk
import XCTest

class StderrCaptureTests: XCTestCase {
    private var originalTracer: DDTracer!

    override func setUp() {
        DDTestMonitor._env_recreate(env: ["DD_API_KEY": "fakeToken", "DD_DISABLE_TEST_INSTRUMENTING": "1"])
        originalTracer = DDTestMonitor.tracer
    }

    override func tearDown() {
        DDTestMonitor.tracer = originalTracer
    }

    /// Install a DDTracer wired to an in-memory `LogRecordExporter` as
    /// the global `DDTestMonitor.tracer` (which `StderrCapture` routes
    /// through) so the test can introspect what the SDK emitted.
    private func installCapturingTracer(_ exporter: InMemoryLogRecordExporter) -> DDTracer {
        let tracer = DDTracer(logRecordExporter: exporter)
        DDTestMonitor.tracer = tracer
        return tracer
    }

    func testWhenErrorHappens_messageIsForwardedAsLogRecord() {
        let logExporter = InMemoryLogRecordExporter()
        let tracer = installCapturingTracer(logExporter)
        let stringToCapture = "2020-10-22 12:01:33.161546+0200 xctest[91153:14310375] This should be captured"

        let spanData = tracer.withActiveSpan(name: "Unnamed", attributes: [:]) { span in
            StderrCapture.stderrMessage(string: stringToCapture)
            Thread.sleep(forTimeInterval: 0.5)
            span.status = .ok
            return span.toSpanData()
        }

        XCTAssertEqual(spanData.events.count, 0,
                       "stderr is now emitted as an OTel LogRecord, not as a span event")

        let records = logExporter.getFinishedLogRecords()
        XCTAssertEqual(records.count, 1)
        let record = records[0]
        XCTAssertEqual(record.body?.description, "This should be captured",
                       "system-log prefix is stripped before forwarding")
        XCTAssertEqual(record.severity, .info)
        let expectedTimestamp = StderrCapture.logDateFormatter.date(from: "2020-10-22 12:01:33.161546+0200")!
        XCTAssertEqual(record.timestamp, expectedTimestamp)
        XCTAssertEqual(record.spanContext?.spanId, spanData.spanId)
        XCTAssertEqual(record.spanContext?.traceId, spanData.traceId)
    }

    func testWhenUIStepHappens_messageIsForwardedAsLogRecord() {
        let logExporter = InMemoryLogRecordExporter()
        let tracer = installCapturingTracer(logExporter)
        let stringToCapture = "    t =     0.50s Open com.datadoghq.DemoSwift"
        let spanStart = Date()

        let spanData = tracer.withActiveSpan(name: "Unnamed", attributes: [:], startTime: spanStart) { span in
            StderrCapture.stderrMessage(string: stringToCapture)
            Thread.sleep(forTimeInterval: 0.5)
            span.status = .ok
            return span.toSpanData()
        }

        XCTAssertEqual(spanData.events.count, 0)

        let records = logExporter.getFinishedLogRecords()
        XCTAssertEqual(records.count, 1)
        let record = records[0]
        XCTAssertEqual(record.body?.description, "Open com.datadoghq.DemoSwift")
        XCTAssertEqual(record.timestamp, spanStart.addingTimeInterval(0.5))
        XCTAssertEqual(record.spanContext?.spanId, spanData.spanId)
    }

    func testStderrInitialises() {
        StderrCapture.startCapturing()
        NSLog("This string should be captured")
        StderrCapture.syncData()
        StderrCapture.stopCapturing()
    }
}
