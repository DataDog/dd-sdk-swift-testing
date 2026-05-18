/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import OpenTelemetrySdk
import XCTest

class StdoutCaptureTests: XCTestCase {
    override func setUp() {
        DDTestMonitor._env_recreate(env: ["DD_API_KEY": "fakeToken", "DD_DISABLE_TEST_INSTRUMENTING": "1"])
    }

    override func tearDown() {
        DDTestMonitor._env_recreate()
    }

    /// Captured stdout is forwarded to the OTel LoggerProvider as a
    /// `LogRecord` — the active test span itself is no longer mutated.
    /// The full LogRecord round-trip is covered by the integration tests;
    /// here we just assert the capture hook drained the buffer and the
    /// span saw no events.
    func testWhenPrintIsCalledAndIsCapturing_stringIsForwardedToLogger() {
        let tracer = DDTracer()
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
    }

    func testWhenPrintIsCalledAndIsNotCapturing_stringIsNotCaptured() {
        let tracer = DDTracer()
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
    }

    func testWhenSomeCharactersAreWrittenToStdoutWithoutNewLines_charactersAreCapturedButNotForwarded() {
        let tracer = DDTestMonitor.tracer
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
    }
}
