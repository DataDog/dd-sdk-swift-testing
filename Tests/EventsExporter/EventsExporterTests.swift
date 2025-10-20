/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import OpenTelemetryApi
@testable import OpenTelemetrySdk
import XCTest
import TestUtils

class EventsExporterTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func testWhenExportSpanIsCalled_thenTraceAndLogsAreUploaded() throws {
        let server = HttpTestServer(url: URL(string: "http://127.0.0.1:33333"))
        try server.start()
        defer { server.stop() }
        
        let instrumentationLibraryName = "SimpleExporter"
        let instrumentationLibraryVersion = "semver:0.1.0"
        
        let exporterConfiguration = ExporterConfiguration(serviceName: "serviceName",
                                                          applicationName: "applicationName",
                                                          applicationVersion: "applicationVersion",
                                                          environment: "environment",
                                                          hostname: "hostname",
                                                          apiKey: "apikey",
                                                          endpoint: .other(
                                                            testsBaseURL: URL(string: "http://127.0.0.1:33333")!,
                                                            logsBaseURL: URL(string: "http://127.0.0.1:33333")!
                                                          ),
                                                          metadata: .init(),
                                                          performancePreset: .readAllFiles,
                                                          exporterId: "exporterId",
                                                          logger: Log())
        
        let datadogExporter = try! EventsExporter(config: exporterConfiguration)
        
        let spanProcessor = SimpleSpanProcessor(spanExporter: datadogExporter)
        defer { spanProcessor.shutdown() }
        
        OpenTelemetry.registerTracerProvider(tracerProvider:
            TracerProviderBuilder()
                .add(spanProcessor: spanProcessor)
                .build()
        )
        let tracer = OpenTelemetry.instance.tracerProvider.get(instrumentationName: instrumentationLibraryName, instrumentationVersion: instrumentationLibraryVersion) as! TracerSdk
        
        simpleSpan(tracer: tracer)
        
        var logsSent = false
        var tracesSent = false
        while !(tracesSent && logsSent) {
            guard let request = server.waitForRequest(timeout: 20, remove: true) else {
                XCTFail("Request not received")
                return
            }
            if request.head.uri.hasPrefix("/api/v2/citestcycle") {
                tracesSent = true
            } else if request.head.uri.hasPrefix("/api/v2/logs") {
                logsSent = true
            }
        }
        
        XCTAssertTrue(logsSent)
        XCTAssertTrue(tracesSent)
    }

    private func simpleSpan(tracer: TracerSdk) {
        let span = tracer.spanBuilder(spanName: "SimpleSpan").setSpanKind(spanKind: .client).startSpan()
        span.addEvent(name: "My event", timestamp: Date())
        span.end()
    }
}
