/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import OpenTelemetryApi
@testable import EventsExporter
@testable import OpenTelemetrySdk
import XCTest

class EventsExporterTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func testWhenExportSpanIsCalled_thenTraceAndLogsAreUploaded() throws {
        try XCTSkipIf(true)
        var logsSent = false
        var tracesSent = false
        let expecTrace = expectation(description: "trace received")
        expecTrace.assertForOverFulfill = false
        let expecLog = expectation(description: "logs received")
        expecLog.assertForOverFulfill = false

        let server = HttpTestServer(url: URL(string: "http://localhost:33333"),
                                    config: HttpTestServerConfig(tracesReceivedCallback: {
                                                                     tracesSent = true
                                                                     expecTrace.fulfill()
                                                                 },
                                                                 logsReceivedCallback: {
                                                                     logsSent = true
                                                                     expecLog.fulfill()
                                                                 }))
        DispatchQueue.global(qos: .default).async {
            do {
                try server.start()
            } catch {
                XCTFail()
                return
            }
        }
        let instrumentationLibraryName = "SimpleExporter"
        let instrumentationLibraryVersion = "semver:0.1.0"

        let tracer = OpenTelemetrySDK.instance.tracerProvider.get(instrumentationName: instrumentationLibraryName, instrumentationVersion: instrumentationLibraryVersion) as! TracerSdk

        let exporterConfiguration = ExporterConfiguration(serviceName: "serviceName",
                                                          libraryVersion: "0.0",
                                                          applicationName: "applicationName",
                                                          applicationVersion: "applicationVersion",
                                                          environment: "environment",
                                                          apiKey: "apikey",
                                                          endpoint: Endpoint.custom(
                                                              testsURL: URL(string: "http://localhost:33333/traces")!,
                                                              logsURL: URL(string: "http://localhost:33333/logs")!
                                                          ))

        let datadogExporter = try! EventsExporter(config: exporterConfiguration)

        let spanProcessor = SimpleSpanProcessor(spanExporter: datadogExporter)
        OpenTelemetrySDK.instance.tracerProvider.addSpanProcessor(spanProcessor)

        simpleSpan(tracer: tracer)
        spanProcessor.shutdown()

        let result = XCTWaiter().wait(for: [expecTrace, expecLog], timeout: 20, enforceOrder: false)

        if result == .completed {
            XCTAssertTrue(logsSent)
            XCTAssertTrue(tracesSent)
        } else {
            XCTFail()
        }

        server.stop()
    }

    private func simpleSpan(tracer: TracerSdk) {
        let span = tracer.spanBuilder(spanName: "SimpleSpan").setSpanKind(spanKind: .client).startSpan()
        span.addEvent(name: "My event", timestamp: Date())
        span.end()
    }
}
