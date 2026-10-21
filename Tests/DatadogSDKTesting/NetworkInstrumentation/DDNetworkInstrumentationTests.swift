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
        let tracer = DDTestMonitor.instance!.tracer
        tracer.tracerProviderSdk.addSpanProcessor(testSpanProcessor)
        DDTestMonitor.instance?.networkInstrumentation = DDNetworkInstrumentation(tracer: tracer, injectHeaders: true)
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
        try DDTestMonitor.instance!.tracer.withActiveSpan(name: "containerSpan", attributes: [:]) { span in
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

    func testItCreatesOneSpanForAsyncDataRequest() async throws {
        // On watchOS `data(from:)` re-enters the public `dataTask(with:)` factory from inside the
        // outer task, so the request is seen both by the resume swizzle and by the factory
        // swizzle. Only one span must be started for it, and it must be ended.
        guard #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) else {
            throw XCTSkip("async URLSession API is not available")
        }
        let server = try XCTUnwrap(self.server)
        let url = server.baseURL.appendingPathComponent("success")
        let tracer = try XCTUnwrap(DDTestMonitor.instance?.tracer)

        let status = try await tracer.withActiveSpan(name: "containerSpan", attributes: [:]) { _ in
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode
        }
        XCTAssertEqual(status, 200)

        let isRequestSpan = { (span: ReadableSpan) in
            span.toSpanData().attributes["http.url"]?.description == url.absoluteString
        }
        // The span may be ended by the task delegate slightly after `data(from:)` returns.
        let deadline = Date().addingTimeInterval(10)
        while testSpanProcessor.endedSpans.filter(isRequestSpan).isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(testSpanProcessor.startedSpans.filter(isRequestSpan).count, 1)
        XCTAssertEqual(testSpanProcessor.endedSpans.filter(isRequestSpan).count, 1)
    }

    func testItEndsSpanForTaskWithoutCompletionHandlerResumedInTask() async throws {
        // The factory swizzle starts the span and resume must not start another one, but it still
        // has to install the task delegate: without a completion handler or a session delegate,
        // nothing else would report the completion and end the span.
        guard #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) else {
            throw XCTSkip("URLSessionTask.delegate is not available")
        }
        let server = try XCTUnwrap(self.server)
        let url = server.baseURL.appendingPathComponent("success")
        let tracer = try XCTUnwrap(DDTestMonitor.instance?.tracer)

        let task = await tracer.withActiveSpan(name: "containerSpan", attributes: [:]) { _ in
            let task = URLSession.shared.dataTask(with: url)
            task.resume()
            return task
        }

        let isRequestSpan = { (span: ReadableSpan) in
            span.toSpanData().attributes["http.url"]?.description == url.absoluteString
        }
        let deadline = Date().addingTimeInterval(10)
        while testSpanProcessor.endedSpans.filter(isRequestSpan).isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(task.state, .completed)
        XCTAssertEqual(testSpanProcessor.startedSpans.filter(isRequestSpan).count, 1)
        let ended = testSpanProcessor.endedSpans.filter(isRequestSpan)
        XCTAssertEqual(ended.count, 1)
        XCTAssertEqual(ended.first?.toSpanData().attributes["http.status_code"]?.description, "200")
    }

    func testItInstrumentsInheritedDelegateMethodsOnce() throws {
        // `SubclassSessionDelegate` implements no delegate method of its own, so the startup scan
        // skips it and it is only discovered when its task resumes. Its methods resolve to the ones
        // of `BaseSessionDelegate`, which must not be wrapped a second time.
        try withContainerSpan { _ in
            DDInstrumentationControl.startPayloadCapture()
            defer { DDInstrumentationControl.stopPayloadCapture() }

            let server = try XCTUnwrap(self.server)
            let url = server.baseURL.appendingPathComponent("success")

            for delegate in [BaseSessionDelegate(), SubclassSessionDelegate()] {
                delegate.completed = expectation(description: "GET \(url) with \(type(of: delegate))")
                let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
                defer { session.finishTasksAndInvalidate() }
                let task = session.dataTask(with: url)
                task.resume()
                waitForExpectations(timeout: 30) { _ in
                    task.cancel()
                }

                let spanData = try XCTUnwrap(testSpanProcessor.lastProcessedSpan).toSpanData()
                XCTAssertEqual(spanData.attributes["http.status_code"]?.description, "200")
                XCTAssertEqual(spanData.attributes["http.response.payload"]?.description,
                               String(data: delegate.received, encoding: .ascii),
                               "\(type(of: delegate))")
            }
        }
    }
}

private class BaseSessionDelegate: NSObject, URLSessionDataDelegate {
    var received = Data()
    var completed: XCTestExpectation?

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        received.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        completed?.fulfill()
    }
}

private final class SubclassSessionDelegate: BaseSessionDelegate {}
