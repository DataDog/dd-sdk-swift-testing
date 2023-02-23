/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

@testable import DatadogSDKTesting
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest

class DDNetworkInstrumentationTests: XCTestCase {
    var containerSpan: Span?
    let testSpanProcessor = SpySpanProcessor()

    override func setUp() {
        XCTAssertNil(DDTracer.activeSpan)
        DDEnvironmentValues.environment[ConfigurationValues.DD_API_KEY.rawValue] = "fakeToken"
        DDEnvironmentValues.environment[ConfigurationValues.DD_DISABLE_TEST_INSTRUMENTING.rawValue] = "1"
        DDTestMonitor.env = DDEnvironmentValues()
        DDTestMonitor.instance = DDTestMonitor()
        DDTestMonitor.instance?.instrumentationWorkQueue.waitUntilAllOperationsAreFinished()
        let tracer = DDTestMonitor.tracer
        tracer.tracerProviderSdk.addSpanProcessor(testSpanProcessor)
        DDTestMonitor.instance?.networkInstrumentation = DDNetworkInstrumentation()
        DDTestMonitor.instance?.injectHeaders = true // This is the default
        let spanName = "containerSpan"
        containerSpan = tracer.startSpan(name: spanName, attributes: [:])
    }

    override func tearDown() {
        containerSpan?.end()
        XCTAssertNil(DDTracer.activeSpan)
    }

    func testItInterceptsDataTaskWithURL() throws {
        var testSpan: RecordEventsReadableSpan

        let url = URL(string: "http://httpbin.org/get")!
        let expec = expectation(description: "GET \(url)")
        var task: URLSessionTask
        task = URLSession.shared.dataTask(with: url) { _, _, _ in
            expec.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 30) { _ in
            task.cancel()
        }

        testSpan = try XCTUnwrap(testSpanProcessor.lastProcessedSpan)
        let spanData = testSpan.toSpanData()
        XCTAssertEqual(spanData.name, "HTTP GET")
        XCTAssertNotNil(spanData.attributes["http.status_code"]?.description)
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

    func testItInterceptsDataTaskWithURLRequest() throws {
        var testSpan: RecordEventsReadableSpan
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
        waitForExpectations(timeout: 30) { _ in
            task.cancel()
        }

        testSpan = try XCTUnwrap(testSpanProcessor.lastProcessedSpan)
        let spanData = testSpan.toSpanData()
        XCTAssertEqual(spanData.name, "HTTP GET")
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

    func testItReturnsErrorStatusForHTTPErrorStatus() {
        var testSpan: RecordEventsReadableSpan?

        let url = URL(string: "http://httpbin.org/status/404")!
        let expec = expectation(description: "GET \(url)")
        var task: URLSessionTask
        task = URLSession.shared.dataTask(with: url) { _, _, _ in
            expec.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 30) { _ in
            task.cancel()
        }
        testSpan = testSpanProcessor.lastProcessedSpan
        let spanData = testSpan!.toSpanData()
        XCTAssertEqual(spanData.name, "HTTP GET")
        XCTAssertTrue(spanData.status.isError)
        XCTAssertEqual(spanData.attributes["http.status_code"]?.description, "404")
    }

    func testItReturnsErrorStatusForNetworkErrors() {
        var testSpan: RecordEventsReadableSpan?

        let url = URL(string: "http://127.0.0.1/404")!
        let expec = expectation(description: "GET \(url)")
        var task: URLSessionTask
        task = URLSession.shared.dataTask(with: url) { _, _, _ in
            expec.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 30) { _ in
            task.cancel()
        }

        testSpan = testSpanProcessor.lastProcessedSpan
        let spanData = testSpan!.toSpanData()
        XCTAssertEqual(spanData.name, "HTTP GET")
        XCTAssertTrue(spanData.status.isError)
    }

    func testItInjectTracingHeaders() throws {
        let url = URL(string: "http://httpbin.org/headers")!
        let expec = expectation(description: "Headers \(url)")
        var task: URLSessionTask

        var data: Data?
        task = URLSession.shared.dataTask(with: url) { response, _, _ in
            data = response
            expec.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 30) { _ in
            task.cancel()
        }

        let json = try JSONSerialization.jsonObject(with: try XCTUnwrap(data), options: .fragmentsAllowed) as? NSDictionary

        let headers = (try XCTUnwrap(json))["headers"] as? NSDictionary

        XCTAssertNotNil(headers?.object(forKey: "Traceparent"))
        XCTAssertNotNil(headers?.object(forKey: "X-Datadog-Origin"))
        XCTAssertNotNil(headers?.object(forKey: "X-Datadog-Parent-Id"))
        XCTAssertNotNil(headers?.object(forKey: "X-Datadog-Trace-Id"))
        XCTAssertEqual(headers?.object(forKey: "X-Datadog-Origin") as! String, "ciapp-test")

        let currentTraceId = try XCTUnwrap(containerSpan?.context.traceId)
        XCTAssertEqual(headers?.object(forKey: "X-Datadog-Trace-Id") as! String, String(currentTraceId.rawLowerLong))
    }
}
