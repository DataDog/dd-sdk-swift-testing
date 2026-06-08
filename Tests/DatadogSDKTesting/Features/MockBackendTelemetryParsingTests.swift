/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import TestUtils
import XCTest

/// Unit coverage for `MockBackend.parseTelemetry`, the decoder the integration
/// tests use to assert telemetry reached the backend. Exercises the wire format
/// directly so the parser is verified without running the integration harness.
final class MockBackendTelemetryParsingTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testParsesMessageBatchMetricsDistributionsAndEvents() {
        // A `message-batch` envelope carrying a count metric, a distribution, and app-closing.
        let batch = data("""
        {
          "api_version": "v2", "request_type": "message-batch",
          "tracer_time": 1, "runtime_id": "r", "seq_id": 1,
          "application": {}, "host": {},
          "payload": [
            {"request_type": "generate-metrics", "payload": {"namespace": "civisibility", "series": [
              {"metric": "git.command", "type": "count", "tags": ["command:get_repository"], "points": [[1.0, 2.0]]}
            ]}},
            {"request_type": "distributions", "payload": {"namespace": "civisibility", "series": [
              {"metric": "endpoint_payload.bytes", "tags": ["endpoint:code_coverage"], "points": [2048.0, 4096.0]}
            ]}},
            {"request_type": "app-closing", "payload": {}}
          ]
        }
        """)

        let parsed = MockBackend.parseTelemetry([batch])

        XCTAssertEqual(parsed.metrics.count, 1)
        let metric = try? XCTUnwrap(parsed.metrics.first)
        XCTAssertEqual(metric?.metric, "git.command")
        XCTAssertEqual(metric?.type, "count")
        XCTAssertEqual(metric?.tags, ["command:get_repository"])
        XCTAssertEqual(metric?.points, [2.0])  // value of the [timestamp, value] pair

        XCTAssertEqual(parsed.distributions.count, 1)
        let dist = try? XCTUnwrap(parsed.distributions.first)
        XCTAssertEqual(dist?.metric, "endpoint_payload.bytes")
        XCTAssertNil(dist?.type)
        XCTAssertEqual(dist?.tags, ["endpoint:code_coverage"])
        XCTAssertEqual(dist?.points.sorted(), [2048.0, 4096.0])  // raw samples

        XCTAssertEqual(parsed.events, ["message-batch", "generate-metrics", "distributions", "app-closing"])
    }

    func testParsesDirectAppStartedEnvelope() {
        // app-started is sent directly (no message-batch wrapper).
        let batch = data("""
        {"api_version": "v2", "request_type": "app-started", "tracer_time": 1,
         "application": {}, "host": {}, "payload": {"configuration": []}}
        """)

        let parsed = MockBackend.parseTelemetry([batch])

        XCTAssertTrue(parsed.events.contains("app-started"))
        XCTAssertTrue(parsed.metrics.isEmpty)
        XCTAssertTrue(parsed.distributions.isEmpty)
    }

    func testAggregatesAcrossBatchesAndIgnoresGarbage() {
        let m1 = data("""
        {"request_type": "generate-metrics", "payload": {"series": [
          {"metric": "a", "type": "count", "points": [[0, 1]]}
        ]}}
        """)
        let m2 = data("""
        {"request_type": "generate-metrics", "payload": {"series": [
          {"metric": "b", "type": "count", "points": [[0, 2]]}
        ]}}
        """)
        let garbage = data("<not-json>")

        let parsed = MockBackend.parseTelemetry([m1, garbage, m2])

        XCTAssertEqual(Set(parsed.metrics.map(\.metric)), ["a", "b"])
        XCTAssertEqual(parsed.metrics.first(where: { $0.metric == "a" })?.points, [1.0])
    }
}
