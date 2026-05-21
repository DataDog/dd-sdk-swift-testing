/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import OpenTelemetryApi
@testable import OpenTelemetrySdk
import TestUtils
import XCTest

class SpanEventsLogTests: XCTestCase {
    func testSpanEventsLogExporterAdapter_writesOneLogPerSpanEvent() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let configuration = ExporterConfiguration(serviceName: "service",
                                                  applicationName: "app",
                                                  applicationVersion: "1.0",
                                                  environment: "test",
                                                  hostname: nil,
                                                  apiKey: "apikey",
                                                  endpoint: .other(
                                                    testsBaseURL: server.baseURL,
                                                    logsBaseURL: server.baseURL
                                                  ),
                                                  metadata: .init(),
                                                  performancePreset: .readAllFiles,
                                                  exporterId: "exporter",
                                                  logger: Log())
        let api = LogsApiService(config: APIServiceConfig(configuration: configuration),
                                 httpClient: HTTPClient(debug: false),
                                 log: configuration.logger)
        let logsExporter = try LogsExporter(config: configuration, api: api)
        let adapter = SpanEventsLogExporterAdapter(logRecordExporter: logsExporter)

        let span = makeSpanData(events: [
            SpanData.Event(name: "event-1", timestamp: Date(), attributes: ["k": .string("v")]),
            SpanData.Event(name: "event-2", timestamp: Date(), attributes: ["k": .string("v")]),
        ])

        let result = adapter.export(spans: [span], explicitTimeout: nil)

        XCTAssertEqual(result, .success)
        // Both events get written; under the `.readAllFiles` preset they may
        // land in separate upload batches, so poll for the total log count.
        let deadline = Date().addingTimeInterval(20)
        while server.requests.allLogs.count < 2, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertEqual(server.requests.allLogs.count, 2)
    }

    // MARK: - helpers

    private func makeSpanData(events: [SpanData.Event]) -> SpanData {
        var resource = Resource()
        resource.service = "service"
        resource.applicationVersion = "1.0"
        resource.environment = "test"
        return SpanData(traceId: TraceId(),
                        spanId: SpanId(),
                        traceFlags: TraceFlags(),
                        traceState: TraceState(),
                        resource: resource,
                        instrumentationScope: InstrumentationScopeInfo(),
                        name: "span",
                        kind: .server,
                        startTime: Date(timeIntervalSinceReferenceDate: 3000),
                        events: events,
                        endTime: Date(timeIntervalSinceReferenceDate: 3001),
                        hasRemoteParent: false)
    }
}
