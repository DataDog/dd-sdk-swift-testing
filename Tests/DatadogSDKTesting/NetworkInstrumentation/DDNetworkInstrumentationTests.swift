/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import DatadogSDKTesting
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest

class DDNetworkInstrumentationTests: XCTestCase {
    var containerSpan: Span?
    let testSpanProcessor = SpySpanProcessor()

    override func setUp() {
        DDEnvironmentValues.environment["DATADOG_CLIENT_TOKEN"] = "fakeToken"
        DDTestMonitor.instance = DDTestMonitor()
        let tracer = DDTestMonitor.instance!.tracer
        OpenTelemetrySDK.instance.tracerProvider.addSpanProcessor(testSpanProcessor)
        DDTestMonitor.instance?.networkInstrumentation = DDNetworkInstrumentation()
        DDTestMonitor.instance?.injectHeaders = true // This is the default
        let spanName = "containerSpan"
        containerSpan = tracer.startSpan(name: spanName, attributes: [:])
    }

    override func tearDown() {
        containerSpan?.end()
    }

    func testItInterceptsDataTaskWithURL() {
        var testSpan: RecordEventsReadableSpan?

        let url = URL(string: "http://httpbin.org/get")!
        let expec = expectation(description: "GET \(url)")
        var task: URLSessionTask
        task = URLSession.shared.dataTask(with: url) { _, _, _ in
            expec.fulfill()
        }
        task.resume()
        testSpan = testSpanProcessor.lastProcessedSpan as? RecordEventsReadableSpan
        waitForExpectations(timeout: 30) { _ in
            task.cancel()
        }

        let spanData = testSpan!.toSpanData()
        XCTAssertEqual(spanData.name, "HTTP GET")
        XCTAssertEqual(spanData.attributes.count, 10)
        XCTAssertEqual(spanData.attributes["http.status_code"]?.description, "200")
        XCTAssertEqual(spanData.attributes["http.scheme"]?.description, "http")
        XCTAssertEqual(spanData.attributes["net.peer.name"]?.description, "httpbin.org")
        XCTAssertEqual(spanData.attributes["http.url"]?.description, "http://httpbin.org/get")
        XCTAssertEqual(spanData.attributes["http.method"]?.description, "GET")
        XCTAssertEqual(spanData.attributes["http.target"]?.description, "/get")
        XCTAssertFalse(spanData.attributes["http.request.headers"]?.description.isEmpty ?? true)
        XCTAssertEqual(spanData.attributes["http.request.payload"]?.description, "<disabled>")
        XCTAssertEqual(spanData.attributes["http.response.payload"]?.description, "<disabled>")
        XCTAssertFalse(spanData.attributes["http.response.headers"]?.description.isEmpty ?? true)
    }

    func testItInterceptsDataTaskWithURLRequest() {
        var testSpan: RecordEventsReadableSpan?
        DDInstrumentationControl.startPayloadCapture()
        DDInstrumentationControl.stopInjectingHeaders()

        let url = URL(string: "http://httpbin.org/get")!
        let urlRequest = URLRequest(url: url)
        let expec = expectation(description: "GET \(url)")
        var task: URLSessionTask
        task = URLSession.shared.dataTask(with: urlRequest) { _, _, _ in
            expec.fulfill()
        }
        task.resume()
        testSpan = testSpanProcessor.lastProcessedSpan as? RecordEventsReadableSpan
        waitForExpectations(timeout: 30) { _ in
            task.cancel()
        }

        let spanData = testSpan!.toSpanData()
        XCTAssertEqual(spanData.name, "HTTP GET")
        XCTAssertEqual(spanData.attributes.count, 10)
        XCTAssertEqual(spanData.attributes["http.status_code"]?.description, "200")
        XCTAssertEqual(spanData.attributes["http.scheme"]?.description, "http")
        XCTAssertEqual(spanData.attributes["net.peer.name"]?.description, "httpbin.org")
        XCTAssertEqual(spanData.attributes["http.url"]?.description, "http://httpbin.org/get")
        XCTAssertEqual(spanData.attributes["http.method"]?.description, "GET")
        XCTAssertEqual(spanData.attributes["http.target"]?.description, "/get")
        XCTAssertTrue(spanData.attributes["http.request.headers"]?.description.isEmpty ?? true)
        XCTAssertEqual(spanData.attributes["http.request.payload"]!.description, "<empty>")
        XCTAssert(spanData.attributes["http.response.payload"]!.description.count > 20)

        DDInstrumentationControl.stopPayloadCapture()
        DDInstrumentationControl.startInjectingHeaders()
    }
}
