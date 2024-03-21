/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest

class DDTracerTests: XCTestCase {
    override func setUp() {
        XCTAssertNil(DDTracer.activeSpan)
        setEnv(env: [:])
    }

    override func tearDown() {
        XCTAssertNil(DDTracer.activeSpan)
        DDTestMonitor._env_recreate()
        OpenTelemetry.registerTracerProvider(tracerProvider: DefaultTracerProvider.instance)
    }

    func testWhenCalledStartSpanAttributes_spanIsCreatedWithAttributes() {
        let tracer = DDTracer()
        let attributes = ["myKey": "myValue"]
        let spanName = "myName"

        let span = tracer.startSpan(name: spanName, attributes: attributes) as! RecordEventsReadableSpan

        let spanData = span.toSpanData()
        XCTAssertEqual(spanData.name, spanName)
        XCTAssertEqual(spanData.attributes.count, 1)
        XCTAssertEqual(spanData.attributes["myKey"]?.description, "myValue")

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
        XCTAssertTrue(tracer.endpointURLs().contains("https://citestcycle-intake.datadoghq.com/api/v2/citestcycle"))
        XCTAssertTrue(tracer.endpointURLs().contains("https://logs.browser-intake-datadoghq.com/api/v2/logs"))
    }

    func testEndpointChangeToUS() {
        setEnv(env: ["DD_ENDPOINT": "US"])

        let tracer = DDTracer()
        XCTAssertTrue(tracer.endpointURLs().contains("https://citestcycle-intake.datadoghq.com/api/v2/citestcycle"))
        XCTAssertTrue(tracer.endpointURLs().contains("https://logs.browser-intake-datadoghq.com/api/v2/logs"))
    }

    func testEndpointChangeToUS3() {
        setEnv(env: ["DD_ENDPOINT": "us3"])

        let tracer = DDTracer()
        XCTAssertTrue(tracer.endpointURLs().contains("https://citestcycle-intake.us3.datadoghq.com/api/v2/citestcycle"))
        XCTAssertTrue(tracer.endpointURLs().contains("https://logs.browser-intake-us3-datadoghq.com/api/v2/logs"))
    }

    func testEndpointChangeToUS5() {
        setEnv(env: ["DD_ENDPOINT": "us5"])
        let tracer = DDTracer()
        XCTAssertTrue(tracer.endpointURLs().contains("https://citestcycle-intake.us5.datadoghq.com/api/v2/citestcycle"))
        XCTAssertTrue(tracer.endpointURLs().contains("https://logs.browser-intake-us5-datadoghq.com/api/v2/logs"))
    }

    func testEndpointChangeToEU() {
        setEnv(env: ["DD_ENDPOINT": "eu"])
        let tracer = DDTracer()
        XCTAssertTrue(tracer.endpointURLs().contains("https://citestcycle-intake.datadoghq.eu/api/v2/citestcycle"))
        XCTAssertTrue(tracer.endpointURLs().contains("https://mobile-http-intake.logs.datadoghq.eu/api/v2/logs"))
    }
    
    func testEndpointChangeToAP1() {
        setEnv(env: ["DD_ENDPOINT": "ap1"])
        let tracer = DDTracer()
        XCTAssertTrue(tracer.endpointURLs().contains("https://citestcycle-intake.ap1.datadoghq.com/api/v2/citestcycle"))
        XCTAssertTrue(tracer.endpointURLs().contains("https://logs.browser-intake-ap1-datadoghq.com/api/v2/logs"))
    }

//    func testEndpointChangeToGov() {
//        DDEnvironmentValues.environment["DD_ENDPOINT"] = "GOV"
//        resetEnvironmentVariables()
//
//        let tracer = DDTracer()
//        XCTAssertTrue(tracer.endpointURLs().contains("https://trace.browser-intake-ddog-gov.com/api/v2/spans"))
//        XCTAssertTrue(tracer.endpointURLs().contains("https://logs.browser-intake-ddog-gov.com/api/v2/logs"))
//        DDEnvironmentValues.environment["DD_ENDPOINT"] = nil
//    }

    func testEnvironmentContext() {
        let testTraceId = TraceId(fromHexString: "ff000000000000000000000000000041")
        let testSpanId = SpanId(fromHexString: "ff00000000000042")
        
        setEnv(env: ["ENVIRONMENT_TRACER_TRACEID": testTraceId.hexString,
                     "ENVIRONMENT_TRACER_SPANID": testSpanId.hexString])

        let tracer = DDTracer()

        let propagationContext = tracer.propagationContext
        XCTAssertEqual(propagationContext?.traceId, testTraceId)
        XCTAssertEqual(propagationContext?.spanId, testSpanId)
    }

    func testCreateSpanFromCrashAndEnvironmentContext() {
        let testTraceId = TraceId(fromHexString: "ff000000000000000000000000000041")
        let testSpanId = SpanId(fromHexString: "ff00000000000042")
        
        setEnv(env: ["ENVIRONMENT_TRACER_TRACEID": testTraceId.hexString,
                     "ENVIRONMENT_TRACER_SPANID": testSpanId.hexString])

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
    }

    func testLogStringAppUI() throws {
        let testTraceId = TraceId(fromHexString: "ff000000000000000000000000000041")
        let testSpanId = SpanId(fromHexString: "ff00000000000042")
        
        setEnv(env: ["ENVIRONMENT_TRACER_TRACEID": testTraceId.hexString,
                     "ENVIRONMENT_TRACER_SPANID": testSpanId.hexString])

        let tracer = DDTracer()
        let testSpanProcessor = SpySpanProcessor()
        tracer.tracerProviderSdk.addSpanProcessor(testSpanProcessor)

        tracer.logString(string: "Hello World", date: Date(timeIntervalSince1970: 1212))
        tracer.flush()
        let span = try XCTUnwrap(testSpanProcessor.lastProcessedSpan)

        let spanData = span.toSpanData()
        XCTAssertEqual(spanData.events.count, 1)
    }

    func testEnvironmentConstantPropagation() {
        let tracer = DDTracer()
        let spanName = "myName"

        let span = tracer.startSpan(name: spanName, attributes: [:]) as! RecordEventsReadableSpan
        let spanData = span.toSpanData()
        let environmentValues = tracer.environmentPropagationHTTPHeaders()

        XCTAssertNotNil(environmentValues["TRACEPARENT"])
        XCTAssert(environmentValues["TRACEPARENT"]?.contains(spanData.traceId.hexString) ?? false)
        XCTAssertTrue(environmentValues["TRACEPARENT"]?.contains(spanData.spanId.hexString) ?? false)

        XCTAssertNotNil(environmentValues[DDHeaders.traceIDField.rawValue])
        XCTAssertEqual(environmentValues[DDHeaders.traceIDField.rawValue], String(spanData.traceId.rawLowerLong))
        XCTAssertNotNil(environmentValues[DDHeaders.parentSpanIDField.rawValue])
        XCTAssertEqual(environmentValues[DDHeaders.parentSpanIDField.rawValue], String(spanData.spanId.rawValue))
        XCTAssertNotNil(environmentValues["CI_VISIBILITY_TEST_EXECUTION_ID"])
        XCTAssertEqual(environmentValues["CI_VISIBILITY_TEST_EXECUTION_ID"], String(spanData.traceId.rawLowerLong))

        span.end()
    }

    func testWhenNoContextActivePropagationAreEmpty() {
        let tracer = DDTracer()
        let environmentValues = tracer.environmentPropagationHTTPHeaders()
        let datadogHeaders = tracer.datadogHeaders(forContext: nil)

        XCTAssertTrue(environmentValues.isEmpty)
        XCTAssertTrue(datadogHeaders.isEmpty)
    }

    func testEnvironmentConstantPropagationWithRUMIntegrationDisabled() {
        setEnv(env: ["DD_DISABLE_SDKIOS_INTEGRATION": "1"])

        let tracer = DDTracer()
        let spanName = "myName"

        let span = tracer.startSpan(name: spanName, attributes: [:]) as! RecordEventsReadableSpan
        let spanData = span.toSpanData()
        let environmentValues = tracer.environmentPropagationHTTPHeaders()

        XCTAssertNotNil(environmentValues["TRACEPARENT"])
        XCTAssert(environmentValues["TRACEPARENT"]?.contains(spanData.traceId.hexString) ?? false)
        XCTAssertTrue(environmentValues["TRACEPARENT"]?.contains(spanData.spanId.hexString) ?? false)

        XCTAssertNil(environmentValues[DDHeaders.traceIDField.rawValue])
        XCTAssertNil(environmentValues[DDHeaders.parentSpanIDField.rawValue])

        span.end()
    }
    
    private func setEnv(env: [String: String]) {
        var env = env
        env["DD_API_KEY"] = "fakeToken"
        env["DD_DISABLE_TEST_INSTRUMENTING"] = "1"
        DDTestMonitor._env_recreate(env: env)
    }
}
