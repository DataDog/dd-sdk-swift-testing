/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import DatadogSDKTesting
import XCTest

class StderrCaptureTests: XCTestCase {

    override func setUp() {
        DDEnvironmentValues.environment["DATADOG_CLIENT_TOKEN"] = "fakeToken"
    }

    override func tearDown() {}

    func testWhenWhenErrorHappens_errorIsCapturedAndConvertedToEvents() {
        DDTestMonitor.instance = DDTestMonitor()
        let tracer = DDTestMonitor.instance!.tracer
        let stringToCapture = "2020-10-22 12:01:33.161546+0200 xctest[91153:14310375] This should be captured"
        let capturer = StderrCapture()

        let span = tracer.startSpan(name: "Unnamed", attributes: [:])
        DDTestMonitor.instance?.testObserver?.currentTestSpan = span
        capturer.stderrMessage(tracer: tracer, string: stringToCapture)
        Thread.sleep(forTimeInterval: 0.5)
        span.end()
        let spanData = span.toSpanData()

        XCTAssertEqual(spanData.timedEvents.count, 1)
        XCTAssertEqual(spanData.timedEvents.first?.attributes["message"]?.description, "This should be captured" )

        let timeToCheck = StderrCapture.logDateFormatter.date(from: "2020-10-22 12:01:33.161546+0200")!.timeIntervalSince1970
        XCTAssertEqual(spanData.timedEvents.first?.epochNanos, UInt64(timeToCheck * 1_000_000_000))
    }

    func testWhenWhenUIStepHappens_messageIsCapturedAndConvertedToEvents() {
        DDTestMonitor.instance = DDTestMonitor()
        let tracer = DDTestMonitor.instance!.tracer
        let stringToCapture = "    t =     0.10s Open com.datadoghq.DemoSwift"
        let capturer = StderrCapture()

        let date = Date()
        let span = tracer.startSpan(name: "Unnamed", attributes: [:], date:date)
        DDTestMonitor.instance?.testObserver?.currentTestSpan = span
        capturer.stderrMessage(tracer: tracer, string: stringToCapture)
        Thread.sleep(forTimeInterval: 0.5)
        span.end()
        let spanData = span.toSpanData()

        XCTAssertEqual(spanData.timedEvents.count, 1)
        XCTAssertEqual(spanData.timedEvents.first?.attributes["message"]?.description, "Open com.datadoghq.DemoSwift" )

        let timeToCheck = date.addingTimeInterval(0.1).timeIntervalSince1970
        XCTAssertEqual(spanData.timedEvents.first?.epochNanos,  UInt64(timeToCheck * 1_000_000_000))
    }
}
