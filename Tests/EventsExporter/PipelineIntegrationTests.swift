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

/// End-to-end integration test that drives all three exporter pipelines —
/// stdout-style span-event logs (via `SpanEventsLogExporterAdapter`), native
/// OTel `LogRecord` logs (via `LogsExporter.export(logRecords:)`), and code
/// coverage payloads (via `CoverageExporter.export(coverageData:)`) — and
/// asserts the wire payloads carry the expected fields.
class PipelineIntegrationTests: XCTestCase {
    func testStdoutLogsOTelLogsAndCoverage_arriveWithExpectedFields() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        // -- 1. Build the EventsExporter facade pointing at MockBackend ----------
        let configuration = ExporterConfiguration.mock(environment: "ci",
                                                       performancePreset: .readAllFiles)
        let endpoint: Endpoint = .other(testsBaseURL: server.baseURL, logsBaseURL: server.baseURL)
        let api = TestOptimizationApiService.mock(endpoint: endpoint)
        let storage = try Directory.temporary().createSubdirectory(path: UUID().uuidString)
        defer { try? storage.delete() }
        let datadogExporter = try EventsExporter(config: configuration, api: api, storage: storage)

        // -- 2. Resource the encoders read service / version / env from ---------
        var resource = Resource()
        resource.service = "my-service"
        resource.applicationName = "my-app"
        resource.applicationVersion = "1.2.3"
        resource.environment = "ci"
        resource.sdkLanguage = "swift"
        resource.sdkName = "dd-sdk-swift-testing"
        resource.sdkVersion = "9.9.9"

        // -- 3. TracerProvider wires the EventsExporter as a SpanExporter so
        //       each ended span flows through the MultiSpanExporter composite
        //       (real spans pipeline + SpanEventsLogExporterAdapter). ----------
        let tracerProvider = TracerProviderBuilder()
            .with(resource: resource)
            .add(spanProcessor: SimpleSpanProcessor(spanExporter: datadogExporter))
            .build()
        defer { tracerProvider.shutdown() }
        let tracer = tracerProvider.get(instrumentationName: "integration-test",
                                        instrumentationVersion: "1.0")

        // -- 4. LoggerProvider drives OTel LogRecord -> LogsExporter directly --
        let loggerProvider = LoggerProviderBuilder()
            .with(resource: resource)
            .with(processors: [SimpleLogRecordProcessor(logRecordExporter: datadogExporter.logsExporter)])
            .build()
        let logger = loggerProvider.loggerBuilder(instrumentationScopeName: "integration-test")
            .setIncludeTraceContext(true)
            .build()

        // -- 5a. Span with a stdout-capture-shaped event ------------------------
        //        (matches DDTracer.logString — name "logString", "message" attr)
        let span = tracer.spanBuilder(spanName: "integration-span").startSpan()
        let spanContext = span.context
        span.addEvent(name: "logString",
                      attributes: ["message": .string("hello from stdout")],
                      timestamp: Date())

        // -- 5b. Native OTel log record with severity + body --------------------
        logger.logRecordBuilder()
            .setSpanContext(spanContext)
            .setSeverity(.warn)
            .setBody(.string("hello from OTel logger"))
            .emit()

        span.end()

        // -- 5c. Code coverage payload -----------------------------------------
        let coverageData = CoverageData(
            name: "integration-test",
            files: [],
            workspacePath: URL(fileURLWithPath: "/Users/me/project"),
            resource: resource,
            instrumentationScopeInfo: InstrumentationScopeInfo(),
            context: .test(testSpanId: SpanId(id: 0x1111),
                           suiteId: SpanId(id: 0x2222),
                           sessionId: SpanId(id: 0x3333))
        )
        datadogExporter.export(coverageData: [coverageData])

        // -- 6. Drain the pipelines --------------------------------------------
        _ = datadogExporter.flush()

        // -- 7. Wait for backend to observe everything -------------------------
        XCTAssertTrue(server.waitForSpans(timeout: 10), "Span request not received")
        XCTAssertTrue(server.waitForCoverage(timeout: 10), "Coverage request not received")
        pollUntil(timeout: 10) { server.requests.allLogs.count >= 2 }

        // -- 8. Spans assertions -----------------------------------------------
        let spans = server.requests.allInfoSpans
        XCTAssertEqual(spans.count, 1, "exactly one span should arrive")
        let arrivedSpan = try XCTUnwrap(spans.first)
        XCTAssertEqual(arrivedSpan.service, "my-service")
        XCTAssertEqual(arrivedSpan.name, "integration-span.internal",
                       "DDSpan appends kind to the name when no `type` attribute is present")
        XCTAssertEqual(arrivedSpan.meta["version"], "1.2.3",
                       "applicationVersion is sourced from Resource.applicationVersion")

        // -- 9. Logs assertions -- two entries (1 stdout-style + 1 OTel) -------
        let logs = server.requests.allLogs
        XCTAssertEqual(logs.count, 2, "one log per span event + one OTel log")

        let stdoutLog = try XCTUnwrap(logs.first { $0.message == "hello from stdout" },
                                      "stdout-style log not found")
        let otelLog = try XCTUnwrap(logs.first { $0.message == "hello from OTel logger" },
                                    "OTel log not found")

        XCTAssertEqual(stdoutLog.service, "my-service")
        XCTAssertEqual(stdoutLog.fields["version"]?.stringValue, "1.2.3")
        XCTAssertEqual(stdoutLog.fields["dd.trace_id"]?.stringValue,
                       "\(spanContext.traceId.rawLowerLong)",
                       "span events carry dd.trace_id correlating to the source span")
        XCTAssertEqual(stdoutLog.fields["dd.span_id"]?.stringValue,
                       "\(spanContext.spanId.rawValue)",
                       "span events carry dd.span_id correlating to the source span")

        XCTAssertEqual(otelLog.service, "my-service")
        XCTAssertEqual(otelLog.status, "warn",
                       "Severity.warn maps to DDLog.Status.warn")
        XCTAssertEqual(otelLog.fields["version"]?.stringValue, "1.2.3")
        XCTAssertEqual(otelLog.fields["dd.trace_id"]?.stringValue,
                       "\(spanContext.traceId.rawLowerLong)",
                       "OTel logs inherit the explicitly set span context")
        XCTAssertEqual(otelLog.fields["dd.span_id"]?.stringValue,
                       "\(spanContext.spanId.rawValue)")

        // -- 10. Coverage assertions -------------------------------------------
        let coverages = server.requests.allCoverages
        XCTAssertEqual(coverages.count, 1)
        let coverage = try XCTUnwrap(coverages.first)
        XCTAssertEqual(coverage.testSessionId, 0x3333)
        XCTAssertEqual(coverage.testSuiteId, 0x2222)
        XCTAssertEqual(coverage.spanId, 0x1111)
    }

    // MARK: - helpers

    private func pollUntil(timeout: TimeInterval, _ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}
