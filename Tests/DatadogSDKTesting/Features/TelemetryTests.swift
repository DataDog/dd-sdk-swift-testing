/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
@testable import EventsExporter
import XCTest

final class TelemetryTests: XCTestCase {
    /// Captures the payloads the manager drains on flush so we can assert what
    /// it produced without touching the file/network pipeline.
    final class CaptureExporter: TelemetryPayloadExporter, @unchecked Sendable {
        private let lock = NSLock()
        private var _items: [any TelemetryPayload] = []

        var items: [any TelemetryPayload] { lock.withLock { _items } }
        var metrics: [TelemetryMetric] { items.compactMap { $0 as? TelemetryMetric } }
        var distributions: [TelemetryDistribution] { items.compactMap { $0 as? TelemetryDistribution } }

        func export(item: any TelemetryPayload) { lock.withLock { _items.append(item) } }
        func export(items: [any TelemetryPayload]) { lock.withLock { _items.append(contentsOf: items) } }
        func flush() -> Bool { true }
        func shutdown() {}
    }

    /// A long interval keeps the periodic timers (flush + heartbeat) out of the
    /// way; tests drive `flush()` explicitly. `NoopTelemetryApi` swallows the
    /// `app-started` call.
    private func makeTelemetry(_ exporter: CaptureExporter, distributionCap: Int = 2048) -> Telemetry {
        Telemetry(api: NoopTelemetryApi(), exporter: exporter,
                  exportInterval: 3600, distributionCap: distributionCap)
    }

    // MARK: - Counters

    func testRecordsCounterAsCountSeriesWithTypedTags() throws {
        let exporter = CaptureExporter()
        let telemetry = makeTelemetry(exporter)

        telemetry.metrics.git.command.add(command: .getRepository)
        telemetry.metrics.endpointPayload.requestsErrors.add(errorType: .timeout, endpoint: .testCycle)

        telemetry.flush()

        let series = exporter.metrics.flatMap(\.series)
        let byName = Dictionary(series.map { ($0.metric, $0) }) { a, _ in a }

        let gitCommand = try XCTUnwrap(byName["git.command"])
        XCTAssertEqual(gitCommand.type, .count)
        XCTAssertEqual(gitCommand.points.first?.value, 1)
        XCTAssertEqual(gitCommand.tags, ["command:get_repository"])
        XCTAssertEqual(exporter.metrics.first?.namespace, .civisibility)

        let errors = try XCTUnwrap(byName["endpoint_payload.requests_errors"])
        XCTAssertEqual(errors.tags, ["endpoint:test_cycle", "error_type:timeout"])
    }

    func testCounterAccumulatesDeltaPerInterval() throws {
        let exporter = CaptureExporter()
        let telemetry = makeTelemetry(exporter)

        telemetry.metrics.itrSkippableTests.responseTests.add(7)
        telemetry.metrics.itrSkippableTests.responseTests.add(3)

        telemetry.flush()

        let series = try XCTUnwrap(exporter.metrics.flatMap(\.series)
            .first { $0.metric == "itr_skippable_tests.response_tests" })
        XCTAssertEqual(series.points.first?.value, 10)
    }

    func testFlushClearsBuffersSoNothingIsReEmitted() {
        let exporter = CaptureExporter()
        let telemetry = makeTelemetry(exporter)

        telemetry.metrics.itrSkippableTests.request.add()
        telemetry.flush()
        telemetry.flush()

        // Second flush has nothing to drain — only the first produced a payload.
        XCTAssertEqual(exporter.metrics.flatMap(\.series).count, 1)
    }

    // MARK: - Distributions

    func testRecordsDistributionAsRawSamples() throws {
        let exporter = CaptureExporter()
        let telemetry = makeTelemetry(exporter)

        telemetry.metrics.endpointPayload.bytes.record(2048, endpoint: .codeCoverage)
        telemetry.metrics.endpointPayload.bytes.record(4096, endpoint: .codeCoverage)
        telemetry.metrics.knownTests.responseTests.record(42)

        telemetry.flush()

        let series = exporter.distributions.flatMap(\.series)
        let byName = Dictionary(series.map { ($0.metric, $0) }) { a, _ in a }

        let bytes = try XCTUnwrap(byName["endpoint_payload.bytes"])
        // Raw samples, verbatim — no bucketing/reconstruction.
        XCTAssertEqual(bytes.points.sorted(), [2048, 4096])
        XCTAssertEqual(bytes.tags, ["endpoint:code_coverage"])

        XCTAssertTrue(byName.keys.contains("known_tests.response_tests"))
        XCTAssertEqual(exporter.distributions.first?.namespace, .civisibility)
    }

    func testFullDistributionBufferForcesEarlyFlush() {
        let exporter = CaptureExporter()
        // Cap of 3 samples forces a drain on the third record, before any flush().
        let telemetry = makeTelemetry(exporter, distributionCap: 3)

        telemetry.metrics.knownTests.responseTests.record(1)
        telemetry.metrics.knownTests.responseTests.record(2)
        XCTAssertTrue(exporter.distributions.isEmpty, "not yet at the cap")

        telemetry.metrics.knownTests.responseTests.record(3)

        let points = exporter.distributions.flatMap(\.series)
            .filter { $0.metric == "known_tests.response_tests" }
            .flatMap(\.points)
        XCTAssertEqual(points.sorted(), [1, 2, 3])
    }

    // MARK: - Observer adapters

    func testErrorTypeMapping() {
        XCTAssertEqual(Telemetry.errorType(statusCode: nil), .network)
        XCTAssertEqual(Telemetry.errorType(statusCode: 404), .statusCode4xx)
        XCTAssertEqual(Telemetry.errorType(statusCode: 503), .statusCode5xx)
        XCTAssertEqual(Telemetry.errorType(statusCode: 200), .network)
    }

    func testRequestMetricsObserverForwardsFactsAndDerivesErrorType() {
        final class Box: @unchecked Sendable {
            var requests = 0
            var durationMs: Double?
            var requestBytes: Int?
            var responseBytes: Int?
            var error: Telemetry.ErrorType?
        }
        let box = Box()
        let observer = Telemetry.RequestMetricsObserver(
            onRequest: { box.requests += 1 },
            onDurationMs: { box.durationMs = $0 },
            onRequestBytes: { box.requestBytes = $0 },
            onResponseBytes: { box.responseBytes = $0 },
            onError: { box.error = $0 }
        )

        // A failed request forwards all facts and derives the error type.
        observer.requestFinished(durationMs: 12, requestBytes: 100, responseBytes: 200,
                                 statusCode: 503, transportError: nil, failed: true)
        XCTAssertEqual(box.requests, 1)
        XCTAssertEqual(box.durationMs, 12)
        XCTAssertEqual(box.requestBytes, 100)
        XCTAssertEqual(box.responseBytes, 200)
        XCTAssertEqual(box.error, .statusCode5xx)

        // A successful request does not report an error.
        box.error = nil
        observer.requestFinished(durationMs: 1, requestBytes: 1, responseBytes: 1,
                                 statusCode: 202, transportError: nil, failed: false)
        XCTAssertEqual(box.requests, 2)
        XCTAssertNil(box.error)
    }
}

// MARK: - Test helpers

/// Swallows the direct `app-started` call so tests exercise only the metric
/// collector. Lives here so production `Telemetry.swift` stays free of test-only code.
private struct NoopTelemetryApi: TelemetryApi {
    var endpoint: EventsExporter.Endpoint = .us1
    var headers: [HTTPHeader] = []
    var encoder: JSONEncoder = JSONEncoder()
    var decoder: JSONDecoder = JSONDecoder()
    var endpointURLs: Set<URL> { [] }

    func sendAppStarted(products: TelemetryProducts?, configuration: [TelemetryConfigItem]?,
                        error: TelemetryError?,
                        installSignature: TelemetryInstallSignature?) async throws(APICallError) {}
    func sendAppHeartbeat() async throws(APICallError) {}
    func sendAppClosing() async throws(APICallError) {}
    func sendMetrics(_ series: [TelemetryMetric.Series],
                     namespace: TelemetryMetric.Namespace?) async throws(APICallError) {}
    func sendDistributions(_ series: [TelemetryDistribution.Series],
                           namespace: TelemetryDistribution.Namespace?) async throws(APICallError) {}
    func sendLogs(_ logs: [TelemetryLog]) async throws(APICallError) {}
    func send(batch items: [any TelemetryPayload]) async throws(APICallError) {}
    func send(batch data: Data) async throws(APICallError) {}
}
