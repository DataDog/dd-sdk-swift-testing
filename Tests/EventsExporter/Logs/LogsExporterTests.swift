/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import OpenTelemetryApi
import TestUtils
@testable import OpenTelemetrySdk
import XCTest

class LogsExporterTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func testWhenExportSpanIsCalledAndSpanHasEvent_thenLogIsUploaded() throws {
        let server = HttpTestServer(url: URL(string: "http://127.0.0.1:33333"))
        try server.start()
        defer { server.stop() }

        let configuration = ExporterConfiguration(serviceName: "serviceName",
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

        let logsExporter = try LogsExporter(config: configuration)

        let spanData = createBasicSpanWithEvent()
        logsExporter.exportLogs(fromSpan: spanData)
        
        guard let request = server.waitForRequest(timeout: 30) else {
            XCTFail("Request not received")
            return
        }
        
        XCTAssertTrue(request.head.uri.hasPrefix("/api/v2/logs"))
    }

    private func createBasicSpanWithEvent() -> SpanData {
        return SpanData(traceId: TraceId(),
                        spanId: SpanId(),
                        traceFlags: TraceFlags(),
                        traceState: TraceState(),
                        resource: Resource(),
                        instrumentationScope: InstrumentationScopeInfo(),
                        name: "spanName",
                        kind: .server,
                        startTime: Date(timeIntervalSinceReferenceDate: 3000),
                        events: [SpanData.Event(name: "event", timestamp: Date(), attributes: ["attributeKey": AttributeValue.string("attributeValue")])],
                        endTime: Date(timeIntervalSinceReferenceDate: 3001),
                        hasRemoteParent: false)
    }
}
