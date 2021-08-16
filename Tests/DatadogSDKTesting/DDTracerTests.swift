/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
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

        let span = tracer.startSpan(name: spanName, attributes: attributes) as! RecordEventsReadableSpan

        let spanData = span.toSpanData()
        XCTAssertEqual(spanData.name, spanName)
        XCTAssertEqual(spanData.attributes.count, 2)
        XCTAssertEqual(spanData.attributes["_dd.origin"]?.description, "ciapp-test")
        XCTAssertEqual(spanData.attributes["myKey"]?.description, "myValue")

        span.end()
    }

    func testWhenCalledStartSpanWithoutAttributes_spanIsCreatedWithJustOriginAttributes() {
        let tracer = DDTracer()
        let spanName = "myName"

        let span = tracer.startSpan(name: spanName, attributes: [:]) as! RecordEventsReadableSpan

        let spanData = span.toSpanData()

        XCTAssertEqual(spanData.name, spanName)
        XCTAssertEqual(spanData.attributes.count, 1)
        XCTAssertEqual(spanData.attributes["_dd.origin"]?.description, "ciapp-test")

        span.end()
    }

    func testTracePropagationHTTPHeadersCalledWithAnActiveSpan_returnTraceIdAndSpanId() {
        let tracer = DDTracer()
        let spanName = "myName"

        let span = tracer.startSpan(name: spanName, attributes: [:]) as! RecordEventsReadableSpan
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
        let simpleSpan = SimpleSpanData(traceIdHi: 1, traceIdLo: 2, spanId: 3, name: "name", startTime: Date(timeIntervalSinceReferenceDate: 33), stringAttributes: [:])
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
        XCTAssertEqual(spanData.spanId, SpanId(id: 3))
        XCTAssertEqual(spanData.attributes[DDTestTags.testStatus], AttributeValue.string(DDTagValues.statusFail))
        XCTAssertEqual(spanData.status, Status.error(description: errorMessage))
        XCTAssertEqual(spanData.attributes[DDTags.errorType], AttributeValue.string(errorType))
        XCTAssertEqual(spanData.attributes[DDTags.errorMessage], AttributeValue.string(errorMessage))
        XCTAssertEqual(spanData.attributes[DDTags.errorStack], AttributeValue.string(errorStack))
        XCTAssertEqual(spanData.endTime, spanData.startTime.addingTimeInterval(TimeInterval.fromMicroseconds(1)))
    }

    func testAddingTagsWithOpenTelemetry() {
        let tracer = DDTracer()
        let spanName = "myName"
        let span = tracer.startSpan(name: spanName, attributes: [:]) as! RecordEventsReadableSpan

        // Get active Span with OpentelemetryApi and set tags
        OpenTelemetry.instance.contextProvider.activeSpan?.setAttribute(key: "OTTag", value: "OTValue")

        let spanData = span.toSpanData()

        XCTAssertEqual(spanData.attributes["OTTag"], AttributeValue.string("OTValue"))
        span.end()
    }

    func testEndpointIsUSByDefault() {
        let tracer = DDTracer()
        XCTAssertTrue(tracer.endpointURLs().contains("https://public-trace-http-intake.logs.datadoghq.com/v1/input/"))
    }

    func testEndpointChangeToUS() {
        DDEnvironmentValues.environment["DD_ENDPOINT"] = "US"
        let tracer = DDTracer()
        XCTAssertTrue(tracer.endpointURLs().contains("https://public-trace-http-intake.logs.datadoghq.com/v1/input/"))
        DDEnvironmentValues.environment["DD_ENDPOINT"] = nil
    }

    func testEndpointChangeToUS3() {
        DDEnvironmentValues.environment["DD_ENDPOINT"] = "us3"
        let tracer = DDTracer()
        XCTAssertTrue(tracer.endpointURLs().contains("https://trace.browser-intake-us3-datadoghq.com/v1/input/"))
        DDEnvironmentValues.environment["DD_ENDPOINT"] = nil
    }

    func testEndpointChangeToEU() {
        DDEnvironmentValues.environment["DD_ENDPOINT"] = "eu"
        let tracer = DDTracer()
        XCTAssertTrue(tracer.endpointURLs().contains("https://public-trace-http-intake.logs.datadoghq.eu/v1/input/"))
        DDEnvironmentValues.environment["DD_ENDPOINT"] = nil
    }

    func testEndpointChangeToGov() {
        DDEnvironmentValues.environment["DD_ENDPOINT"] = "GOV"
        let tracer = DDTracer()
        XCTAssertTrue(tracer.endpointURLs().contains("https://trace.browser-intake-ddog-gov.com/v1/input/"))
        DDEnvironmentValues.environment["DD_ENDPOINT"] = nil
    }

    func testEnvironmentContext() {
        let testTraceId = TraceId(fromHexString: "ff000000000000000000000000000041")
        let testSpanId = SpanId(fromHexString: "ff00000000000042")

        DDEnvironmentValues.environment["ENVIRONMENT_TRACER_TRACEID"] = testTraceId.hexString
        DDEnvironmentValues.environment["ENVIRONMENT_TRACER_SPANID"] = testSpanId.hexString

        let tracer = DDTracer()

        let propagationContext = tracer.propagationContext
        XCTAssertEqual(propagationContext?.traceId, testTraceId)
        XCTAssertEqual(propagationContext?.spanId, testSpanId)

        DDEnvironmentValues.environment["ENVIRONMENT_TRACER_TRACEID"] = nil
        DDEnvironmentValues.environment["ENVIRONMENT_TRACER_SPANID"] = nil
    }

    func testCreateSpanFromCrashAndEnvironmentContext() {
        let testTraceId = TraceId(fromHexString: "ff000000000000000000000000000041")
        let testSpanId = SpanId(fromHexString: "ff00000000000042")

        DDEnvironmentValues.environment["ENVIRONMENT_TRACER_TRACEID"] = testTraceId.hexString
        DDEnvironmentValues.environment["ENVIRONMENT_TRACER_SPANID"] = testSpanId.hexString

        let simpleSpan = SimpleSpanData(traceIdHi: testTraceId.idHi, traceIdLo: testTraceId.idLo, spanId: 3, name: "name", startTime: Date(timeIntervalSinceReferenceDate: 33), stringAttributes: [:])
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
        XCTAssertEqual(spanData.traceId, testTraceId)
        XCTAssertEqual(spanData.attributes[DDTestTags.testStatus], AttributeValue.string(DDTagValues.statusFail))
        XCTAssertEqual(spanData.status, Status.error(description: errorMessage))
        XCTAssertEqual(spanData.attributes[DDTags.errorType], AttributeValue.string(errorType))
        XCTAssertEqual(spanData.attributes[DDTags.errorMessage], AttributeValue.string(errorMessage))
        XCTAssertEqual(spanData.attributes[DDTags.errorStack], AttributeValue.string(errorStack))
        XCTAssertEqual(spanData.endTime, spanData.startTime.addingTimeInterval(TimeInterval.fromMicroseconds(1)))

        DDEnvironmentValues.environment["ENVIRONMENT_TRACER_TRACEID"] = nil
        DDEnvironmentValues.environment["ENVIRONMENT_TRACER_SPANID"] = nil
    }

    func testLogStringAppUI() {
        let testTraceId = TraceId(fromHexString: "ff000000000000000000000000000041")
        let testSpanId = SpanId(fromHexString: "ff00000000000042")

        DDEnvironmentValues.environment["ENVIRONMENT_TRACER_TRACEID"] = testTraceId.hexString
        DDEnvironmentValues.environment["ENVIRONMENT_TRACER_SPANID"] = testSpanId.hexString

        let testSpanProcessor = SpySpanProcessor()
        OpenTelemetrySDK.instance.tracerProvider.addSpanProcessor(testSpanProcessor)

        let tracer = DDTracer()

        tracer.logString(string: "Hello World", date: Date(timeIntervalSince1970: 1212))
        tracer.flush()
        let span = testSpanProcessor.lastProcessedSpan!

        let spanData = span.toSpanData()
        XCTAssertEqual(spanData.events.count, 1)

        DDEnvironmentValues.environment["ENVIRONMENT_TRACER_TRACEID"] = nil
        DDEnvironmentValues.environment["ENVIRONMENT_TRACER_SPANID"] = nil
    }

    func testEnvironmentConstantPropagation() {
        let tracer = DDTracer()
        let spanName = "myName"

        let span = tracer.startSpan(name: spanName, attributes: [:]) as! RecordEventsReadableSpan
        let spanData = span.toSpanData()
        let environmentValues = tracer.environmentPropagationHTTPHeaders()

        XCTAssertNotNil(environmentValues["OTEL_TRACE_PARENT"])
        XCTAssert(environmentValues["OTEL_TRACE_PARENT"]?.contains(spanData.traceId.hexString) ?? false)
        XCTAssertTrue(environmentValues["OTEL_TRACE_PARENT"]?.contains(spanData.spanId.hexString) ?? false)
        span.end()
    }

    func testWhenNoContextActivePropagationAreEmpty() {
        let tracer = DDTracer()
        let environmentValues = tracer.environmentPropagationHTTPHeaders()
        let datadogHeaders = tracer.datadogHeaders(forContext: nil)

        XCTAssertTrue(environmentValues.isEmpty)
        XCTAssertTrue(datadogHeaders.isEmpty)
    }
}
