/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import OpenTelemetryApi
@testable import OpenTelemetrySdk
import XCTest
import TestUtils

class TelemetryLogExporterTests: XCTestCase {

    // MARK: - Helpers

    private func makeExporter(server: MockBackend) throws -> TelemetryLogExporter {
        let endpoint: Endpoint = .other(testsBaseURL: server.baseURL, logsBaseURL: server.baseURL)
        let config = ExporterConfiguration.mock(performancePreset: .readAllFiles)
        let api = TelemetryApiService.mock(endpoint: endpoint)
        let storage = try Directory.temporary().createSubdirectory(path: UUID().uuidString)
        let telemetryExporter = try TelemetryExporter(config: config, storage: storage, api: api)
        return TelemetryLogExporter(telemetryExporter: telemetryExporter)
    }

    private func record(
        body: AttributeValue? = .string("test message"),
        severity: Severity? = .info,
        attributes: [String: AttributeValue] = [:],
        timestamp: Date = Date(timeIntervalSince1970: 1_000),
        observedTimestamp: Date? = nil,
        eventName: String? = nil
    ) -> ReadableLogRecord {
        ReadableLogRecord(
            resource: Resource(),
            instrumentationScopeInfo: InstrumentationScopeInfo(),
            timestamp: timestamp,
            observedTimestamp: observedTimestamp,
            severity: severity,
            body: body,
            attributes: attributes,
            eventName: eventName
        )
    }

    private func receivedLog(from server: MockBackend) throws -> [String: Any] {
        let raw = try XCTUnwrap(server.requests.telemetry.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [[String: Any]])
        let logsEntry = try XCTUnwrap(payload.first(where: { $0["request_type"] as? String == "logs" }))
        let logsPayload = try XCTUnwrap(logsEntry["payload"] as? [String: Any])
        let logs = try XCTUnwrap(logsPayload["logs"] as? [[String: Any]])
        return try XCTUnwrap(logs.first)
    }

    // MARK: - Empty input

    func testExport_emptyRecords_returnsSuccess() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        XCTAssertEqual(exporter.export(logRecords: [], explicitTimeout: nil), .success)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(server.requests.telemetry.isEmpty)
    }

    // MARK: - Message extraction

    func testExport_bodyPresent_usesBodyAsMessage() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        XCTAssertEqual(exporter.export(logRecords: [record(body: .string("from body"))], explicitTimeout: nil), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let log = try receivedLog(from: server)
        XCTAssertEqual(log["message"] as? String, "from body")
    }

    func testExport_noBody_usesMessageAttribute() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let r = record(body: nil, attributes: ["message": .string("from attribute")])
        XCTAssertEqual(exporter.export(logRecords: [r], explicitTimeout: nil), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let log = try receivedLog(from: server)
        XCTAssertEqual(log["message"] as? String, "from attribute")
    }

    func testExport_noBodyOrAttribute_usesEventName() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let r = record(body: nil, attributes: [:], eventName: "my.event")
        XCTAssertEqual(exporter.export(logRecords: [r], explicitTimeout: nil), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let log = try receivedLog(from: server)
        XCTAssertEqual(log["message"] as? String, "my.event")
    }

    func testExport_noBodyAttributeOrEventName_usesDefaultMessage() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let r = record(body: nil, attributes: [:], eventName: nil)
        XCTAssertEqual(exporter.export(logRecords: [r], explicitTimeout: nil), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let log = try receivedLog(from: server)
        XCTAssertEqual(log["message"] as? String, "Log event")
    }

    // MARK: - Severity → Level mapping

    func testExport_errorSeverity_mapsToErrorLevel() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        // Test one representative from each error/fatal group
        let records = [Severity.error, .error4, .fatal, .fatal4].map { record(severity: $0) }
        XCTAssertEqual(exporter.export(logRecords: records, explicitTimeout: nil), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let raw = try XCTUnwrap(server.requests.telemetry.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [[String: Any]])
        let logsEntry = try XCTUnwrap(payload.first(where: { $0["request_type"] as? String == "logs" }))
        let logs = try XCTUnwrap((logsEntry["payload"] as? [String: Any])?["logs"] as? [[String: Any]])
        XCTAssertEqual(logs.count, 4)
        XCTAssertTrue(logs.allSatisfy { $0["level"] as? String == "ERROR" })
    }

    func testExport_warnSeverity_mapsToWarnLevel() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let records = [Severity.warn, .warn2, .warn3, .warn4].map { record(severity: $0) }
        XCTAssertEqual(exporter.export(logRecords: records, explicitTimeout: nil), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let raw = try XCTUnwrap(server.requests.telemetry.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [[String: Any]])
        let logsEntry = try XCTUnwrap(payload.first(where: { $0["request_type"] as? String == "logs" }))
        let logs = try XCTUnwrap((logsEntry["payload"] as? [String: Any])?["logs"] as? [[String: Any]])
        XCTAssertEqual(logs.count, 4)
        XCTAssertTrue(logs.allSatisfy { $0["level"] as? String == "WARN" })
    }

    func testExport_otherSeverities_mapToDebugLevel() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let records = ([Severity.trace, .debug, .info] + [nil]).map { record(severity: $0) }
        XCTAssertEqual(exporter.export(logRecords: records, explicitTimeout: nil), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let raw = try XCTUnwrap(server.requests.telemetry.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [[String: Any]])
        let logsEntry = try XCTUnwrap(payload.first(where: { $0["request_type"] as? String == "logs" }))
        let logs = try XCTUnwrap((logsEntry["payload"] as? [String: Any])?["logs"] as? [[String: Any]])
        XCTAssertEqual(logs.count, 4)
        XCTAssertTrue(logs.allSatisfy { $0["level"] as? String == "DEBUG" })
    }

    // MARK: - Stack trace

    func testExport_withStackTrace_extractsStackTraceAttribute() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let r = record(attributes: ["exception.stacktrace": .string("frame1\nframe2")])
        XCTAssertEqual(exporter.export(logRecords: [r], explicitTimeout: nil), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let log = try receivedLog(from: server)
        XCTAssertEqual(log["stack_trace"] as? String, "frame1\nframe2")
        // exception.stacktrace must NOT appear in tags
        let tags = log["tags"] as? String
        XCTAssertNil(tags?.contains("exception.stacktrace"))
    }

    // MARK: - Tags from attributes

    func testExport_withAttributes_producesTagString() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let r = record(attributes: ["env": .string("prod"), "version": .string("1.0")])
        XCTAssertEqual(exporter.export(logRecords: [r], explicitTimeout: nil), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let log = try receivedLog(from: server)
        let tags = try XCTUnwrap(log["tags"] as? String)
        // Tags are sorted alphabetically
        XCTAssertEqual(tags, "env:prod,version:1.0")
    }

    func testExport_withNoAttributes_tagsIsNil() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        XCTAssertEqual(exporter.export(logRecords: [record(attributes: [:])], explicitTimeout: nil), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let log = try receivedLog(from: server)
        XCTAssertNil(log["tags"])
    }

    func testExport_messageAttributeConsumed_doesNotAppearInTags() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let r = record(body: nil, attributes: ["message": .string("the msg"), "env": .string("test")])
        XCTAssertEqual(exporter.export(logRecords: [r], explicitTimeout: nil), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let log = try receivedLog(from: server)
        XCTAssertEqual(log["message"] as? String, "the msg")
        // "message" key must be consumed, only "env" remains in tags
        XCTAssertEqual(log["tags"] as? String, "env:test")
    }

    // MARK: - Timestamp

    func testExport_observedTimestampPreferredOverTimestamp() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let r = record(
            timestamp: Date(timeIntervalSince1970: 1000),
            observedTimestamp: Date(timeIntervalSince1970: 2000)
        )
        XCTAssertEqual(exporter.export(logRecords: [r], explicitTimeout: nil), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let log = try receivedLog(from: server)
        XCTAssertEqual(log["tracer_time"] as? Int, 2000)
    }

    func testExport_noObservedTimestamp_fallsBackToTimestamp() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let r = record(timestamp: Date(timeIntervalSince1970: 1234), observedTimestamp: nil)
        XCTAssertEqual(exporter.export(logRecords: [r], explicitTimeout: nil), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let log = try receivedLog(from: server)
        XCTAssertEqual(log["tracer_time"] as? Int, 1234)
    }

    // MARK: - Multiple records in one call

    func testExport_multipleRecords_allForwarded() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let records = [
            record(body: .string("one"), severity: .error),
            record(body: .string("two"), severity: .warn),
            record(body: .string("three"), severity: .info),
        ]
        XCTAssertEqual(exporter.export(logRecords: records, explicitTimeout: nil), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let raw = try XCTUnwrap(server.requests.telemetry.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [[String: Any]])
        let logsEntry = try XCTUnwrap(payload.first(where: { $0["request_type"] as? String == "logs" }))
        let logsPayload = try XCTUnwrap(logsEntry["payload"] as? [String: Any])
        let logs = try XCTUnwrap(logsPayload["logs"] as? [[String: Any]])
        XCTAssertEqual(logs.count, 3)
        XCTAssertEqual(Set(logs.compactMap { $0["message"] as? String }), ["one", "two", "three"])
    }

    // MARK: - forceFlush / shutdown

    func testForceFlush_returnsSuccess() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        XCTAssertEqual(exporter.forceFlush(explicitTimeout: nil), .success)
    }
}
