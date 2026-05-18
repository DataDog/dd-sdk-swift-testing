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
    func testWhenExportSpanIsCalledAndSpanHasEvent_thenLogIsUploaded() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let configuration = ExporterConfiguration(serviceName: "serviceName",
                                                  applicationName: "applicationName",
                                                  applicationVersion: "applicationVersion",
                                                  environment: "environment",
                                                  hostname: "hostname",
                                                  apiKey: "apikey",
                                                  endpoint: .other(
                                                    testsBaseURL: server.baseURL,
                                                    logsBaseURL: server.baseURL
                                                  ),
                                                  metadata: .init(),
                                                  performancePreset: .readAllFiles,
                                                  exporterId: "exporterId",
                                                  logger: Log())

        let api = LogsApiService(
            config: APIServiceConfig(configuration: configuration),
            httpClient: HTTPClient(debug: false),
            log: configuration.logger
        )
        let logsExporter = try LogsExporter(config: configuration, api: api)

        let spanData = createBasicSpanWithEvent()
        logsExporter.exportLogs(fromSpan: spanData)

        guard server.waitForLogs(timeout: 20) else {
            XCTFail("Request not received")
            return
        }

        XCTAssertTrue(server.requests.allLogs.count == 1)
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
