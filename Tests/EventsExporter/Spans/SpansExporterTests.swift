/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import OpenTelemetryApi
@testable import EventsExporter
@testable import OpenTelemetrySdk
import XCTest

class SpansExporterTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func testWhenExportSpanIsCalled_thenTraceIsUploaded() throws {
        //try XCTSkipIf(true)
        var tracesSent = false
        let expec = expectation(description: "traces received")
        let server = HttpTestServer(url: URL(string: "http://localhost:33333"),
                                    config: HttpTestServerConfig(tracesReceivedCallback: {
                                                                     tracesSent = true
                                                                     expec.fulfill()
                                                                 },
                                                                 logsReceivedCallback: nil))

        DispatchQueue.global(qos: .default).async {
            do {
                try server.start()
            } catch {
                XCTFail()
                return
            }
        }

        let configuration = ExporterConfiguration(serviceName: "serviceName",
                                                  libraryVersion: "0.0",
                                                  applicationName: "applicationName",
                                                  applicationVersion: "applicationVersion",
                                                  environment: "environment",
                                                  hostname: nil,
                                                  apiKey: "apikey",
                                                  applicationKey: "applicationkey",
                                                  endpoint: Endpoint.custom(
                                                      testsURL: URL(string: "http://localhost:33333/traces")!,
                                                      logsURL: URL(string: "http://localhost:33333/logs")!
                                                  ),
                                                  performancePreset: .instantDataDelivery,
                                                  exporterId: "exporterId",
                                                  debugMode: false)

        let spansExporter = try SpansExporter(config: configuration)

        let spanData = createBasicSpan()
        spansExporter.exportSpan(span: spanData)

        waitForExpectations(timeout: 30) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                XCTFail()
            }
        }
        XCTAssertTrue(tracesSent)

        server.stop()
    }

    private func createBasicSpan() -> SpanData {
        return SpanData(traceId: TraceId(),
                        spanId: SpanId(),
                        traceFlags: TraceFlags(),
                        traceState: TraceState(),
                        resource: Resource(),
                        instrumentationScope: InstrumentationScopeInfo(),
                        name: "spanName",
                        kind: .server,
                        startTime: Date(timeIntervalSinceReferenceDate: 3000),
                        endTime: Date(timeIntervalSinceReferenceDate: 3001),
                        hasRemoteParent: false)
    }
}
