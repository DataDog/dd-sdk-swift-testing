/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest
import TestUtils

class DDNetworkInstrumentationTests: XCTestCase {
    let testSpanProcessor = SpySpanProcessor()
    var server: HttpTestServer?

    override func setUpWithError() throws {
        XCTAssertNil(DDTracer.activeSpan)
        server = HttpTestServer(config: .init())
        DDTestMonitor._env_recreate(env: ["DD_API_KEY": "fakeToken", "DD_DISABLE_TEST_INSTRUMENTING": "1"])
        DDTestMonitor.instance = DDTestMonitor()
        DDTestMonitor.instance?.instrumentationWorkQueue.waitUntilAllOperationsAreFinished()
        let tracer = DDTestMonitor.tracer
        tracer.tracerProviderSdk.addSpanProcessor(testSpanProcessor)
        DDTestMonitor.instance?.networkInstrumentation = DDNetworkInstrumentation()
        DDTestMonitor.instance?.injectHeaders = true // This is the default
        try server?.start()
    }

    override func tearDown() {
        DDTestMonitor.instance?.stop()
        DDTestMonitor.instance = nil
        DDTestMonitor._env_recreate()
        server?.stop()
        server = nil
        XCTAssertNil(DDTracer.activeSpan)
    }
    
    func withContainerSpan<T>(_ body: (any Span) throws -> T) rethrows -> T {
        try DDTestMonitor.tracer.withActiveSpan(name: "containerSpan", attributes: [:]) { span in
            try body(span)
        }
    }

    func testItInterceptsDataTaskWithURL() throws {
        try withContainerSpan { _ in
            var testSpan: SpanSdk
            
            let server = try XCTUnwrap(self.server)
            let url = server.baseURL.appendingPathComponent("success")
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
            XCTAssertEqual(spanData.attributes["http.scheme"]?.description, url.scheme)
            XCTAssertEqual(spanData.attributes["net.peer.name"]?.description, url.host)
            XCTAssertEqual(spanData.attributes["http.url"]?.description, url.absoluteString)
            XCTAssertEqual(spanData.attributes["http.method"]?.description, "GET")
            XCTAssertEqual(spanData.attributes["http.target"]?.description, url.path)
            XCTAssertFalse(spanData.attributes["http.request.headers"]?.description.isEmpty ?? true)
            XCTAssertEqual(spanData.attributes["http.request.payload"]?.description, "<disabled>")
            XCTAssertEqual(spanData.attributes["http.response.payload"]?.description, "<disabled>")
            XCTAssertFalse(spanData.attributes["http.response.headers"]?.description.isEmpty ?? true)
        }
    }

    func testItInterceptsDataTaskWithURLRequest() throws {
        try withContainerSpan { _ in
            var testSpan: SpanSdk
            DDInstrumentationControl.startPayloadCapture()
            DDInstrumentationControl.stopInjectingHeaders()
            
            let server = try XCTUnwrap(self.server)
            let url = server.baseURL.appendingPathComponent("success")
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
            XCTAssertEqual(spanData.attributes["http.scheme"]?.description, url.scheme)
            XCTAssertEqual(spanData.attributes["net.peer.name"]?.description, url.host)
            XCTAssertEqual(spanData.attributes["http.url"]?.description, url.absoluteString)
            XCTAssertEqual(spanData.attributes["http.method"]?.description, "GET")
            XCTAssertEqual(spanData.attributes["http.target"]?.description, url.path)
            XCTAssertTrue(spanData.attributes["http.request.headers"]?.description.isEmpty ?? true)
            XCTAssertEqual(spanData.attributes["http.request.payload"]!.description, "<empty>")
            XCTAssert(spanData.attributes["http.response.payload"]!.description.count > 10)
            
            DDInstrumentationControl.stopPayloadCapture()
            DDInstrumentationControl.startInjectingHeaders()
        }
    }

    func testItReturnsErrorStatusForHTTPErrorStatus() throws {
        try withContainerSpan { _ in
            var testSpan: SpanSdk
            
            let server = try XCTUnwrap(self.server)
            let url = server.baseURL.appendingPathComponent("/error")
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
            XCTAssertTrue(spanData.status.isError)
            XCTAssertEqual(spanData.attributes["http.status_code"]?.description, "400")
        }
    }

    func testItReturnsErrorStatusForNetworkErrors() throws {
        try withContainerSpan { _ in
            var testSpan: SpanSdk?
            
            let server = try XCTUnwrap(self.server)
            let url = server.baseURL.appendingPathComponent("/network-error")
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
    }

    func testItInjectTracingHeaders() throws {
        try withContainerSpan { containerSpan in
            let server = try XCTUnwrap(self.server)
            let url = server.baseURL.appendingPathComponent("headers")
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
            
            let headers = try JSONSerialization.jsonObject(with: try XCTUnwrap(data), options: .fragmentsAllowed) as? NSDictionary
            
            XCTAssertNotNil(headers?.object(forKey: "traceparent"))
            XCTAssertNotNil(headers?.object(forKey: "x-datadog-origin"))
            XCTAssertNotNil(headers?.object(forKey: "x-datadog-parent-id"))
            XCTAssertNotNil(headers?.object(forKey: "x-datadog-trace-id"))
            XCTAssertEqual(headers?.object(forKey: "x-datadog-origin") as? String, "ciapp-test")
            
            let currentTraceId = containerSpan.context.traceId
            XCTAssertEqual(headers?.object(forKey: "x-datadog-trace-id") as? String, String(currentTraceId.rawLowerLong))
        }
    }
}
