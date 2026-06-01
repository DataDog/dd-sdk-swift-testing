/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import XCTest
import TestUtils

class TelemetryExporterTests: XCTestCase {

    // MARK: - Helpers

    private func makeExporter(performancePreset: PerformancePreset,
                               server: MockBackend) throws -> (TelemetryExporter, Directory)
    {
        let endpoint: Endpoint = .other(testsBaseURL: server.baseURL, logsBaseURL: server.baseURL)
        let config = ExporterConfiguration.mock(performancePreset: performancePreset)
        let api = TelemetryApiService.mock(endpoint: endpoint)
        let storage = try Directory.temporary().createSubdirectory(path: UUID().uuidString)
        let exporter = try TelemetryExporter(config: config, storage: storage, api: api)
        return (exporter, storage)
    }

    private func assertValidEnvelope(_ raw: Data,
                                     expectedEntryCount: Int,
                                     file: StaticString = #filePath,
                                     line: UInt = #line) throws
    {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any],
                                 file: file, line: line)
        XCTAssertEqual(json["api_version"] as? String, "v2", file: file, line: line)
        XCTAssertEqual(json["request_type"] as? String, "message-batch", file: file, line: line)
        XCTAssertNotNil(json["runtime_id"], file: file, line: line)
        XCTAssertNotNil(json["application"], file: file, line: line)
        XCTAssertNotNil(json["host"], file: file, line: line)
        let payload = try XCTUnwrap(json["payload"] as? [[String: Any]], file: file, line: line)
        XCTAssertEqual(payload.count, expectedEntryCount, file: file, line: line)
    }

    // MARK: - Single-entry upload

    func testExportMetrics_uploadsWellFormedEnvelope() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let (exporter, storage) = try makeExporter(performancePreset: .readAllFiles, server: server)
        defer { try? storage.delete() }

        let series = TelemetryMetric.Series(
            metric: "test.metric",
            points: [.init(timestamp: 1_000_000, value: 42.0)],
            type: .count,
            tags: ["env:test"]
        )
        exporter.export(item: TelemetryMetric(namespace: .tracers, series: [series]))

        guard server.waitForTelemetry(timeout: 30) else {
            XCTFail("No telemetry batch received")
            return
        }

        let raw = try XCTUnwrap(server.requests.telemetry.first)
        try assertValidEnvelope(raw, expectedEntryCount: 1)
        let payload = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: raw) as? [String: Any])?["payload"] as? [[String: Any]]
        )
        XCTAssertEqual(payload[0]["request_type"] as? String, "generate-metrics")
    }

    func testExportLogs_uploadsWellFormedEnvelope() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let (exporter, storage) = try makeExporter(performancePreset: .readAllFiles, server: server)
        defer { try? storage.delete() }

        exporter.export(item: TelemetryLog.Logs([TelemetryLog(message: "oops", level: .error)]))

        guard server.waitForTelemetry(timeout: 30) else {
            XCTFail("No telemetry batch received")
            return
        }

        let raw = try XCTUnwrap(server.requests.telemetry.first)
        try assertValidEnvelope(raw, expectedEntryCount: 1)
        let payload = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: raw) as? [String: Any])?["payload"] as? [[String: Any]]
        )
        XCTAssertEqual(payload[0]["request_type"] as? String, "logs")
    }

    // MARK: - Multiple entries in one file

    /// When several exports are written before the file is closed they land in
    /// the same on-disk batch. A single upload must wrap them all inside one
    /// `message-batch` payload array.
    func testExportMultipleItems_batchedInOneFile_uploadedAsOneEnvelope() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let (exporter, storage) = try makeExporter(performancePreset: .appendToOneFile, server: server)
        defer { try? storage.delete() }

        let series = TelemetryMetric.Series(metric: "m", points: [.init(timestamp: 1, value: 1)])
        let log = TelemetryLog(message: "msg", level: .debug)
        exporter.export(items: [
            TelemetryMetric(namespace: .general, series: [series]),
            TelemetryLog.Logs([log]),
            TelemetryAppHeartbeat(),
        ])
        // Close the in-progress file and drain it synchronously.
        exporter.flush()

        guard server.waitForTelemetry(count: 1, timeout: 5) else {
            XCTFail("Expected 1 telemetry batch, got \(server.requests.telemetry.count)")
            return
        }
        XCTAssertEqual(server.requests.telemetry.count, 1, "All entries should be in one envelope")

        let raw = try XCTUnwrap(server.requests.telemetry.first)
        try assertValidEnvelope(raw, expectedEntryCount: 3)

        let payload = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: raw) as? [String: Any])?["payload"] as? [[String: Any]]
        )
        print("PAYLOAD", payload)
        let types = Set(payload.compactMap { $0["request_type"] as? String })
        XCTAssertEqual(types, ["generate-metrics", "logs", "app-heartbeat"])
    }

    // MARK: - Multiple entries across separate files

    /// When each export goes to its own file (maxObjectsInFile=1) the upload
    /// worker sends them as separate `message-batch` requests, each containing
    /// exactly one entry.
    func testExportMultipleItems_acrossSeparateFiles_eachUploadedIndependently() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let (exporter, storage) = try makeExporter(
            performancePreset: .writeEachObjectToNewFileAndReadAllFiles, server: server
        )
        defer { try? storage.delete() }

        let series = TelemetryMetric.Series(metric: "m", points: [.init(timestamp: 1, value: 1)])
        let log = TelemetryLog(message: "msg", level: .debug)
        exporter.export(items: [
            TelemetryMetric(namespace: .general, series: [series]),
            TelemetryLog.Logs([log]),
            TelemetryAppHeartbeat(),
        ])

        guard server.waitForTelemetry(count: 3, timeout: 30) else {
            XCTFail("Expected 3 telemetry batches, got \(server.requests.telemetry.count)")
            return
        }

        // Each file becomes its own well-formed envelope containing one entry.
        for raw in server.requests.telemetry {
            try assertValidEnvelope(raw, expectedEntryCount: 1)
        }

        let allTypes = try server.requests.telemetry.flatMap { raw -> [String] in
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
            let payload = try XCTUnwrap(json["payload"] as? [[String: Any]])
            return payload.compactMap { $0["request_type"] as? String }
        }
        XCTAssertEqual(Set(allTypes), ["generate-metrics", "logs", "app-heartbeat"])
    }
}
