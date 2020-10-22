/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import DatadogSDKTesting
import XCTest

class StdoutCaptureTests: XCTestCase {

    override func setUp() {
        DDEnvironmentValues.environment["DATADOG_CLIENT_TOKEN"] = "fakeToken"
    }

    override func tearDown() {}

    func testWhenPrintIsCalledAndIsCapturing_stringIsCapturedAndConvertedToEvents() {
        let tracer = DDTracer()
        let stringToCapture = "This should be captured"

        StdoutCapture.startCapturing(tracer: tracer)
        let span = tracer.startSpan(name: "Unnamed", attributes: [:])
        print(stringToCapture)
        span.end()
        let spanData = span.toSpanData()
        StdoutCapture.stopCapturing()

        XCTAssertTrue(StdoutCapture.stdoutBuffer.isEmpty)
        XCTAssertEqual(spanData.timedEvents.count, 1)
        XCTAssertEqual(spanData.timedEvents.first?.attributes["message"]?.description, stringToCapture + "\n" )
    }

    func testWhenPrintIsCalledAndIsNotCapturing_stringIsNotCaptured() {
        let tracer = DDTracer()
        let stringToCapture = "This should be captured"

        StdoutCapture.startCapturing(tracer: tracer)
        StdoutCapture.stopCapturing()
        let span = tracer.startSpan(name: "Unnamed", attributes: [:])
        print(stringToCapture)
        span.end()
        let spanData = span.toSpanData()

        XCTAssertTrue(StdoutCapture.stdoutBuffer.isEmpty)
        XCTAssertEqual(spanData.timedEvents.count, 0)
    }

    func testWhenSomeCharactersAreWrittenToStdoutWithoutNewLines_charactersAreCapturedButNotConvertedToEvents () {
        let tracer = DDTracer()
        let stringToCapture = "This should  not be captured"

        StdoutCapture.startCapturing(tracer: tracer)
        let span = tracer.startSpan(name: "Unnamed", attributes: [:])
        fputs(stringToCapture, stdout)
        let spanData = span.toSpanData()
        span.end()
        StdoutCapture.stopCapturing()

        XCTAssertFalse(StdoutCapture.stdoutBuffer.isEmpty)
        XCTAssertEqual(StdoutCapture.stdoutBuffer, stringToCapture)
        XCTAssertEqual(spanData.timedEvents.count, 0)
    }
}
