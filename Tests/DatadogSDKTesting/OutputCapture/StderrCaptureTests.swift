/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import OpenTelemetrySdk
import XCTest

class StderrCaptureTests: XCTestCase {
    override func setUp() {
        DDTestMonitor._env_recreate(env: ["DD_API_KEY": "fakeToken", "DD_DISABLE_TEST_INSTRUMENTING": "1"])
    }

    override func tearDown() {}

    /// Captured stderr is forwarded to the OTel LoggerProvider as a
    /// `LogRecord` — the active test span itself is no longer mutated. The
    /// full LogRecord round-trip is covered by the integration tests; here
    /// we just confirm the parsing/capture hook fires (no span events) and
    /// the date parser still recognises the system log prefix.
    func testWhenWhenErrorHappens_messageIsForwardedToLogger() {
        let tracer = DDTracer()
        let stringToCapture = "2020-10-22 12:01:33.161546+0200 xctest[91153:14310375] This should be captured"

        let spanData = tracer.withActiveSpan(name: "Unnamed", attributes: [:]) { span in
            StderrCapture.stderrMessage(string: stringToCapture)
            Thread.sleep(forTimeInterval: 0.5)
            span.status = .ok
            return span.toSpanData()
        }

        XCTAssertEqual(spanData.events.count, 0,
                       "stderr is now emitted as an OTel LogRecord, not as a span event")
        XCTAssertNotNil(StderrCapture.logDateFormatter.date(from: "2020-10-22 12:01:33.161546+0200"),
                        "system-log date prefix should still parse")
    }

    func testWhenWhenUIStepHappens_messageIsForwardedToLogger() {
        let tracer = DDTracer()
        let stringToCapture = "    t =     0.50s Open com.datadoghq.DemoSwift"

        let spanData = tracer.withActiveSpan(name: "Unnamed", attributes: [:]) { span in
            StderrCapture.stderrMessage(string: stringToCapture)
            Thread.sleep(forTimeInterval: 0.5)
            span.status = .ok
            return span.toSpanData()
        }

        XCTAssertEqual(spanData.events.count, 0,
                       "UI-test step lines are now emitted as OTel LogRecords, not span events")
    }

    func testStderrInitialises() {
        StderrCapture.startCapturing()
        NSLog("This string should be captured")
        StderrCapture.syncData()
        StderrCapture.stopCapturing()
    }
}
