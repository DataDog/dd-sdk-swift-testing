/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import DatadogSDKTesting
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest

class DDTracerTests: XCTestCase {
    override func setUp() {
        DDEnvironmentValues.environment["DATADOG_CLIENT_TOKEN"] = "fakeToken"
    }

    override func tearDown() {}

    func testWhenCalledStartSpanAttributes_spanIsCreatedWithAttributes() {
        let tracer = DDTracer()
        let attributes = ["myKey": "myValue"]
        let spanName = "myName"

        let span = tracer.startSpan(name: spanName, attributes: attributes)

        let spanData = span.toSpanData()
        XCTAssertEqual(spanData.name, spanName)
        XCTAssertEqual(spanData.attributes.count, 1)
        XCTAssertEqual(spanData.attributes["myKey"]?.description, "myValue")

        span.end()
    }

    func testWhenCalledStartSpanWithoutAttributes_spanIsCreatedWithoutAttributes() {
        let tracer = DDTracer()
        let spanName = "myName"

        let span = tracer.startSpan(name: spanName, attributes: [:])

        let spanData = span.toSpanData()

        XCTAssertEqual(spanData.name, spanName)
        XCTAssertEqual(spanData.attributes.count, 0)

        span.end()
    }

    func testTracePropagationHTTPHeadersCalledWithAnActiveSpan_returnTraceIdAndSpanId() {
        let tracer = DDTracer()
        let spanName = "myName"

        let span = tracer.startSpan(name: spanName, attributes: [:])
        let spanData = span.toSpanData()
        let headers = tracer.tracePropagationHTTPHeaders()

        XCTAssertEqual(headers[DDHeaders.traceIDField.rawValue], String(spanData.traceId.rawLowerLong))
        XCTAssertEqual(headers[DDHeaders.parentSpanIDField.rawValue], String(spanData.spanId.rawValue))

        span.end()
    }

    func testTracePropagationHTTPHeadersCalledWithNoActiveSpan_returnsEmpty() {
        let tracer = DDTracer()
        let headers = tracer.tracePropagationHTTPHeaders()

        XCTAssertEqual(headers.count, 0)
        print(headers)
    }

    func testCreateSpanFromCrash() {
        let simpleSpan = SimpleSpanData(traceIdHi: 1, traceIdLo: 2, spanId: 3, name: "name", startEpochNanos: 33, stringAttributes: [:])
        let crashDate: Date? = nil
        let errorType = "errorType"
        let errorMessage = "errorMessage"
        let errorStack = "errorStack"

        let tracer = DDTracer()
        let span = tracer.createSpanFromCrash(spanData: simpleSpan,
                                              crashDate: crashDate,
                                              errorType: errorType,
                                              errorMessage: errorMessage,
                                              errorStack: errorStack)
        let spanData = span.toSpanData()

        XCTAssertEqual(spanData.name, "name")
        XCTAssertEqual(spanData.traceId, TraceId(idHi: 1, idLo: 2))
        XCTAssertEqual(spanData.spanId, SpanId(id:3))
        XCTAssertEqual(spanData.attributes[DDTestTags.testStatus],  AttributeValue.string( DDTestTags.statusFail))
        XCTAssertEqual(spanData.status, Status.internalError)
        XCTAssertEqual(spanData.attributes[DDTags.errorType], AttributeValue.string(errorType))
        XCTAssertEqual(spanData.attributes[DDTags.errorMessage], AttributeValue.string(errorMessage))
        XCTAssertEqual(spanData.attributes[DDTags.errorStack], AttributeValue.string(errorStack))
        XCTAssertEqual(spanData.endEpochNanos, spanData.startEpochNanos + 100)
    }
    
}
