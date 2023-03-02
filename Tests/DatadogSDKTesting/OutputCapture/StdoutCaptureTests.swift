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
        DDEnvironmentValues.environment[ConfigurationValues.DD_API_KEY.rawValue] = "fakeKey"
        DDTestMonitor.env = DDEnvironmentValues()
    }

    override func tearDown() {}

    func testWhenPrintIsCalledAndIsCapturing_stringIsCapturedAndConvertedToEvents() {
        let tracer = DDTracer()
        let stringToCapture = "This should be captured"

        StdoutCapture.startCapturing()
        let span = tracer.startSpan(name: "Unnamed", attributes: [:]) as! RecordEventsReadableSpan
        print(stringToCapture)
        span.status = .ok
        span.end()
        let spanData = span.toSpanData()
        DDInstrumentationControl.stopStdoutCapture()

        XCTAssertTrue(StdoutCapture.stdoutBuffer.isEmpty)
        XCTAssertEqual(spanData.events.count, 1)
        XCTAssertEqual(spanData.events.first?.attributes["message"]?.description, stringToCapture + "\n")
    }

    func testWhenPrintIsCalledAndIsNotCapturing_stringIsNotCaptured() {
        let tracer = DDTracer()
        let stringToCapture = "This should be captured"

        DDInstrumentationControl.startStdoutCapture()
        DDInstrumentationControl.stopStdoutCapture()
        let span = tracer.startSpan(name: "Unnamed", attributes: [:]) as! RecordEventsReadableSpan
        print(stringToCapture)
        span.status = .ok
        span.end()
        let spanData = span.toSpanData()

        XCTAssertTrue(StdoutCapture.stdoutBuffer.isEmpty)
        XCTAssertEqual(spanData.events.count, 0)
    }

    func testWhenSomeCharactersAreWrittenToStdoutWithoutNewLines_charactersAreCapturedButNotConvertedToEvents() {
        let tracer = DDTestMonitor.tracer
        let stringToCapture = "This should  not be captured"

        StdoutCapture.startCapturing()
        let span = tracer.startSpan(name: "Unnamed", attributes: [:]) as! RecordEventsReadableSpan
        fputs(stringToCapture, stdout)
        let spanData = span.toSpanData()
        span.status = .ok
        span.end()
        DDInstrumentationControl.stopStdoutCapture()

        XCTAssertFalse(StdoutCapture.stdoutBuffer.isEmpty)
        XCTAssertEqual(StdoutCapture.stdoutBuffer, stringToCapture)
        XCTAssertEqual(spanData.events.count, 0)
    }
}
