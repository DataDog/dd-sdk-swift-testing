/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

@testable import DatadogSDKTesting
import OpenTelemetrySdk
import XCTest

class StderrCaptureTests: XCTestCase {
    override func setUp() {
        DDEnvironmentValues.environment["DATADOG_CLIENT_TOKEN"] = "fakeToken"
        DDEnvironmentValues.environment["DD_DISABLE_TEST_INSTRUMENTING"] = "1"
        DDTestMonitor.env = DDEnvironmentValues()
    }

    override func tearDown() {}

    func testWhenWhenErrorHappens_errorIsCapturedAndConvertedToEvents() {
        DDTestMonitor.instance = DDTestMonitor()
        let tracer = DDTestMonitor.tracer
        let stringToCapture = "2020-10-22 12:01:33.161546+0200 xctest[91153:14310375] This should be captured"
        let capturer = StderrCapture()

        let span = tracer.startSpan(name: "Unnamed", attributes: [:]) as! RecordEventsReadableSpan
        DDTestMonitor.instance?.currentTest?.span = span
        capturer.stderrMessage(tracer: tracer, string: stringToCapture)
        Thread.sleep(forTimeInterval: 0.5)
        span.status = .ok
        span.end()
        let spanData = span.toSpanData()

        XCTAssertEqual(spanData.events.count, 1)
        XCTAssertEqual(spanData.events.first?.attributes["message"]?.description, "This should be captured")

        let timeToCheck = StderrCapture.logDateFormatter.date(from: "2020-10-22 12:01:33.161546+0200")!
        XCTAssertEqual(spanData.events.first?.timestamp, timeToCheck)
    }

    func testWhenWhenUIStepHappens_messageIsCapturedAndConvertedToEvents() {
        DDTestMonitor.instance = DDTestMonitor()
        let tracer = DDTestMonitor.tracer
        let stringToCapture = "    t =     0.50s Open com.datadoghq.DemoSwift"
        let capturer = StderrCapture()

        let date = Date()
        let span = tracer.startSpan(name: "Unnamed", attributes: [:], startTime: date) as! RecordEventsReadableSpan
        DDTestMonitor.instance?.currentTest?.span = span
        capturer.stderrMessage(tracer: tracer, string: stringToCapture)
        Thread.sleep(forTimeInterval: 0.6)
        span.status = .ok
        span.end()
        let spanData = span.toSpanData()

        XCTAssertEqual(spanData.events.count, 1)
        XCTAssertEqual(spanData.events.first?.attributes["message"]?.description, "Open com.datadoghq.DemoSwift")

        let timeToCheck = date.addingTimeInterval(0.5)
        XCTAssertEqual(spanData.events.first?.timestamp, timeToCheck)
    }
}
