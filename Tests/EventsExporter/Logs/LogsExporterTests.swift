/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import OpenTelemetryApi
@testable import EventsExporter
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
        try XCTSkipIf(true)
        var logsSent = false
        let expec = expectation(description: "logs received")
        let server = HttpTestServer(url: URL(string: "http://localhost:33333"),
                                    config: HttpTestServerConfig(tracesReceivedCallback: nil,
                                                                 logsReceivedCallback: {
                                                                     logsSent = true
                                                                     expec.fulfill()
                                                                 }))

        DispatchQueue.global(qos: .default).async {
            do {
                try server.start()
            } catch {
                XCTFail()
                return
            }
        }

        let configuration = ExporterConfiguration(serviceName: "serviceName", libraryVersion: "0.0",
                                                  applicationName: "applicationName",
                                                  applicationVersion: "applicationVersion",
                                                  environment: "environment",
                                                  apiKey: "apikey",
                                                  applicationKey: "applicationkey",
                                                  endpoint: Endpoint.custom(
                                                      testsURL: URL(string: "http://localhost:33333/traces")!,
                                                      logsURL: URL(string: "http://localhost:33333/logs")!
                                                  ),
                                                  performancePreset: .instantDataDelivery,
                                                  exporterId: "exporterId")

        let logsExporter = try LogsExporter(config: configuration)

        let spanData = createBasicSpanWithEvent()
        logsExporter.exportLogs(fromSpan: spanData)

        waitForExpectations(timeout: 30) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                XCTFail()
            }
        }
        XCTAssertTrue(logsSent)

        server.stop()
    }

    private func createBasicSpanWithEvent() -> SpanData {
        return SpanData(traceId: TraceId(),
                        spanId: SpanId(),
                        traceFlags: TraceFlags(),
                        traceState: TraceState(),
                        resource: Resource(),
                        instrumentationLibraryInfo: InstrumentationLibraryInfo(),
                        name: "spanName",
                        kind: .server,
                        startTime: Date(timeIntervalSinceReferenceDate: 3000),
                        events: [SpanData.Event(name: "event", timestamp: Date(), attributes: ["attributeKey": AttributeValue.string("attributeValue")])],
                        endTime: Date(timeIntervalSinceReferenceDate: 3001),
                        hasRemoteParent: false)
    }
}
