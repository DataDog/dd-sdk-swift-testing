/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import OpenTelemetryApi
@testable import EventsExporter
@testable import OpenTelemetrySdk
import XCTest
import TestUtils

class SpansExporterTests: XCTestCase {
    func testWhenExportSpanIsCalled_thenTraceIsUploaded() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let configuration = ExporterConfiguration(serviceName: "serviceName",
                                                  applicationName: "applicationName",
                                                  applicationVersion: "applicationVersion",
                                                  environment: "environment",
                                                  hostname: nil,
                                                  apiKey: "apikey",
                                                  endpoint: .other(
                                                    testsBaseURL: server.baseURL,
                                                    logsBaseURL: server.baseURL
                                                  ),
                                                  metadata: .init(),
                                                  performancePreset: .readAllFiles,
                                                  exporterId: "exporterId",
                                                  logger: Log())

        let api = SpansApiService(
            config: APIServiceConfig(configuration: configuration),
            httpClient: HTTPClient(debug: false),
            log: configuration.logger
        )
        let storage = try Directory.temporary().createSubdirectory(path: UUID().uuidString)
        defer { try? storage.delete() }
        let spansExporter = try SpansExporter(config: configuration, storage: storage, api: api)

        let spanData = createBasicSpan()
        spansExporter.exportSpan(span: spanData)

        guard server.waitForSpans(timeout: 30) else {
            XCTFail("No request received")
            return
        }

        let spans = server.requests.allInfoSpans
        XCTAssertTrue(spans.count == 1)
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
