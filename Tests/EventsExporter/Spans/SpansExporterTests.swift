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

        let configuration = ExporterConfiguration.mock(performancePreset: .readAllFiles)
        let endpoint: Endpoint = .other(testsBaseURL: server.baseURL, logsBaseURL: server.baseURL)
        let api = SpansApiService(
            config: APIServiceConfig.mock(endpoint: endpoint),
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

    func testWhenExportSpanIsCalled_thenMetaAndPayloadMetadataValuesAreTruncated() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let longValue = String(repeating: "m", count: maxMetaStringValueLength + 1)
        var metadata = SpanMetadata()
        metadata[string: "global.long"] = longValue
        let configuration = ExporterConfiguration.mock(metadata: metadata, performancePreset: .readAllFiles)
        let endpoint: Endpoint = .other(testsBaseURL: server.baseURL, logsBaseURL: server.baseURL)
        let api = SpansApiService(
            config: APIServiceConfig.mock(endpoint: endpoint),
            httpClient: HTTPClient(debug: false),
            log: configuration.logger
        )
        let storage = try Directory.temporary().createSubdirectory(path: UUID().uuidString)
        defer { try? storage.delete() }
        let spansExporter = try SpansExporter(config: configuration, storage: storage, api: api)

        let spanData = createBasicSpan(attributes: [
            "custom.long": .string(longValue),
            "custom.metric": .int(42),
        ])
        spansExporter.exportSpan(span: spanData)

        guard server.waitForSpans(timeout: 30) else {
            XCTFail("No request received")
            return
        }

        let span = try XCTUnwrap(server.requests.allInfoSpans.first)
        let truncatedValue = String(longValue.prefix(maxMetaStringValueLength))
        XCTAssertEqual(span.meta["custom.long"], truncatedValue)
        XCTAssertEqual(span.meta["custom.long"]?.count, maxMetaStringValueLength)
        XCTAssertEqual(span.meta["global.long"], truncatedValue)
        XCTAssertEqual(span.metrics["custom.metric"], 42)
    }

    private func createBasicSpan(attributes: [String: AttributeValue] = [:]) -> SpanData {
        return SpanData(traceId: TraceId(),
                        spanId: SpanId(),
                        traceFlags: TraceFlags(),
                        traceState: TraceState(),
                        resource: Resource(),
                        instrumentationScope: InstrumentationScopeInfo(),
                        name: "spanName",
                        kind: .server,
                        startTime: Date(timeIntervalSinceReferenceDate: 3000),
                        attributes: attributes,
                        endTime: Date(timeIntervalSinceReferenceDate: 3001),
                        hasRemoteParent: false)
    }
}
