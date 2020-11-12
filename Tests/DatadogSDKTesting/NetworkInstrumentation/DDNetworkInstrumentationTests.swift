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

    override func setUp() {
        DDEnvironmentValues.environment["DATADOG_CLIENT_TOKEN"] = "fakeToken"
        DDTestMonitor.instance = DDTestMonitor()
        let tracer = DDTestMonitor.instance!.tracer
        DDTestMonitor.instance?.networkInstrumentation = DDNetworkInstrumentation()
        DDTestMonitor.instance?.injectHeaders = true // This is the default
        let spanName = "containerSpan"
        _ = tracer.startSpan(name: spanName, attributes: [:])
    }

    func testItInterceptsDataTaskWithURL() {

        var testSpan: RecordEventsReadableSpan?

        let url = URL(string: "http://httpbin.org/get")!
        let expec = expectation(description: "GET \(url)")
        var task: URLSessionTask
        task = URLSession.shared.dataTask(with: url) { data, response, _ in
            expec.fulfill()
        }
        task.resume()
        let taskIdentifier = DDTestMonitor.instance!.networkInstrumentation!.idKeyForTask(task)
        testSpan = DDNetworkActivityLogger.spanDict[taskIdentifier]
        waitForExpectations(timeout: 30) { error in
            task.cancel()
        }

        let spanData = testSpan!.toSpanData()
        XCTAssertEqual(spanData.name, "HTTP GET")
        XCTAssertEqual(spanData.attributes.count, 9)
        XCTAssertEqual(spanData.attributes["http.status_code"]?.description, "200")
        XCTAssertEqual(spanData.attributes["http.scheme"]?.description, "http")
        XCTAssertEqual(spanData.attributes["net.peer.name"]?.description, "httpbin.org")
        XCTAssertEqual(spanData.attributes["http.url"]?.description, "http://httpbin.org/get")
        XCTAssertEqual(spanData.attributes["http.method"]?.description, "GET")
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
        task = URLSession.shared.dataTask(with: urlRequest) { data, response, _ in
            expec.fulfill()
        }
        task.resume()
        let taskIdentifier = DDTestMonitor.instance!.networkInstrumentation!.idKeyForTask(task)
        testSpan = DDNetworkActivityLogger.spanDict[taskIdentifier]
        waitForExpectations(timeout: 30) { error in
            task.cancel()
        }

        let spanData = testSpan!.toSpanData()
        XCTAssertEqual(spanData.name, "HTTP GET")
        XCTAssertEqual(spanData.attributes.count, 9)
        XCTAssertEqual(spanData.attributes["http.status_code"]?.description, "200")
        XCTAssertEqual(spanData.attributes["http.scheme"]?.description, "http")
        XCTAssertEqual(spanData.attributes["net.peer.name"]?.description, "httpbin.org")
        XCTAssertEqual(spanData.attributes["http.url"]?.description, "http://httpbin.org/get")
        XCTAssertEqual(spanData.attributes["http.method"]?.description, "GET")
        XCTAssertTrue(spanData.attributes["http.request.headers"]?.description.isEmpty ?? true)
        XCTAssertEqual(spanData.attributes["http.request.payload"]!.description, "<empty>")
        XCTAssert(spanData.attributes["http.response.payload"]!.description.count > 20)

        DDInstrumentationControl.stopPayloadCapture()
        DDInstrumentationControl.startInjectingHeaders()
    }
}
