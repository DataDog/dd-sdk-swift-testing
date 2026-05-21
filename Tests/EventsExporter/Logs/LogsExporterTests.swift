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
    func testWhenExportLogRecordsIsCalled_thenLogIsUploaded() throws {
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
        let storage = try Directory.temporary().createSubdirectory(path: UUID().uuidString)
        defer { try? storage.delete() }
        let logsExporter = try LogsExporter(config: configuration, storage: storage, api: api)

        let record = makeLogRecord()
        let result = logsExporter.export(logRecords: [record], explicitTimeout: nil)

        XCTAssertEqual(result, .success)
        guard server.waitForLogs(timeout: 20) else {
            XCTFail("Request not received")
            return
        }
        XCTAssertEqual(server.requests.allLogs.count, 1)
    }

    private func makeLogRecord() -> ReadableLogRecord {
        let spanContext = SpanContext.create(traceId: TraceId(),
                                             spanId: SpanId(),
                                             traceFlags: TraceFlags(),
                                             traceState: TraceState())
        return ReadableLogRecord(resource: Resource(),
                                 instrumentationScopeInfo: InstrumentationScopeInfo(),
                                 timestamp: Date(timeIntervalSinceReferenceDate: 3000),
                                 spanContext: spanContext,
                                 severity: .info,
                                 body: .string("log body"),
                                 attributes: ["attributeKey": AttributeValue.string("attributeValue")])
    }
}
