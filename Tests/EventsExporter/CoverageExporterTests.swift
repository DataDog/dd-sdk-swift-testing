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

class CoverageExporterTests: XCTestCase {
    func testExportCoverageData_uploadsParsedPayload() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let configuration = ExporterConfiguration(
            serviceName: "service",
            applicationName: "app",
            applicationVersion: "1.0",
            environment: "test",
            hostname: nil,
            apiKey: "apikey",
            endpoint: .other(testsBaseURL: server.baseURL, logsBaseURL: server.baseURL),
            metadata: .init(),
            performancePreset: .readAllFiles,
            exporterId: "exporter",
            logger: Log()
        )
        let api = TestImpactAnalysisApiService(config: APIServiceConfig(configuration: configuration),
                                               httpClient: HTTPClient(debug: false),
                                               log: configuration.logger)
        let exporter = try CoverageExporter(config: configuration, api: api)

        let data = CoverageData(
            name: "MyTest",
            files: [],
            workspacePath: URL(fileURLWithPath: "/Users/me/project"),
            resource: Resource(),
            instrumentationScopeInfo: InstrumentationScopeInfo(),
            context: .test(testSpanId: SpanId(id: 0xCAFE),
                           suiteId: SpanId(id: 0xBEEF),
                           sessionId: SpanId(id: 0xDEAD))
        )

        let result = exporter.export(coverageData: [data], explicitTimeout: nil)

        XCTAssertEqual(result, .success)
        guard server.waitForCoverage(timeout: 20) else {
            XCTFail("Coverage payload not received")
            return
        }
        let payload = try XCTUnwrap(server.requests.allCoverages.first)
        XCTAssertEqual(payload.testSessionId, 0xDEAD)
        XCTAssertEqual(payload.testSuiteId, 0xBEEF)
        XCTAssertEqual(payload.spanId, 0xCAFE)
    }

    func testExportSuiteCoverageData_writesZeroTestId() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let configuration = ExporterConfiguration(
            serviceName: "service",
            applicationName: "app",
            applicationVersion: "1.0",
            environment: "test",
            hostname: nil,
            apiKey: "apikey",
            endpoint: .other(testsBaseURL: server.baseURL, logsBaseURL: server.baseURL),
            metadata: .init(),
            performancePreset: .readAllFiles,
            exporterId: "exporter",
            logger: Log()
        )
        let api = TestImpactAnalysisApiService(config: APIServiceConfig(configuration: configuration),
                                               httpClient: HTTPClient(debug: false),
                                               log: configuration.logger)
        let exporter = try CoverageExporter(config: configuration, api: api)

        let data = CoverageData(
            name: "MySuite",
            files: [],
            workspacePath: nil,
            resource: Resource(),
            instrumentationScopeInfo: InstrumentationScopeInfo(),
            context: .suite(suiteSpanId: SpanId(id: 0xBEEF),
                            sessionId: SpanId(id: 0xDEAD))
        )

        XCTAssertEqual(exporter.export(coverageData: [data], explicitTimeout: nil), .success)

        guard server.waitForCoverage(timeout: 20) else {
            XCTFail("Coverage payload not received")
            return
        }
        let payload = try XCTUnwrap(server.requests.allCoverages.first)
        // Suite-level coverage has no test span — it serializes as 0.
        XCTAssertEqual(payload.spanId, 0)
        XCTAssertEqual(payload.testSuiteId, 0xBEEF)
        XCTAssertEqual(payload.testSessionId, 0xDEAD)
    }
}
