/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import EventsExporter
import OpenTelemetryApi
@testable import OpenTelemetrySdk
import XCTest

final class TelemetryTests: XCTestCase {
    /// Captures the `MetricData` pushed on flush so we can assert what the
    /// manager produced without touching the network pipeline.
    final class InMemoryMetricExporter: MetricExporter {
        private(set) var exported: [MetricData] = []

        func export(metrics: [MetricData]) -> ExportResult {
            exported.append(contentsOf: metrics)
            return .success
        }

        func flush() -> ExportResult { .success }
        func shutdown() -> ExportResult { .success }
        func getAggregationTemporality(for instrument: InstrumentType) -> AggregationTemporality {
            .delta
        }
    }

    private func makeTelemetry(_ exporter: MetricExporter) -> Telemetry {
        Telemetry(metricOnlyExporter: exporter, resource: Resource(), exportInterval: 3600)
    }

    func testRecordsCounterWithTypedTags() throws {
        let exporter = InMemoryMetricExporter()
        let telemetry = makeTelemetry(exporter)

        telemetry.metrics.git.command.add(command: .getRepository)
        telemetry.metrics.endpointPayload.requestsErrors.add(errorType: .timeout, endpoint: .testCycle)

        XCTAssertTrue(telemetry.flush())

        let byName = Dictionary(exporter.exported.map { ($0.name, $0) }) { a, _ in a }

        let gitCommand = try XCTUnwrap(byName["git.command"])
        XCTAssertEqual(gitCommand.resource.telemetryMetricNamespace, .civisibility)
        let gitPoint = try XCTUnwrap(gitCommand.data.points.first)
        XCTAssertEqual(gitPoint.attributes["command"]?.description, "get_repository")

        let errors = try XCTUnwrap(byName["endpoint_payload.requests_errors"])
        let errPoint = try XCTUnwrap(errors.data.points.first)
        XCTAssertEqual(errPoint.attributes["error_type"]?.description, "timeout")
        XCTAssertEqual(errPoint.attributes["endpoint"]?.description, "test_cycle")
    }

    func testRecordsDistributionWithCivisibilityNamespace() throws {
        let exporter = InMemoryMetricExporter()
        let telemetry = makeTelemetry(exporter)

        telemetry.metrics.endpointPayload.bytes.record(2048, endpoint: .codeCoverage)
        telemetry.metrics.knownTests.responseTests.record(42)

        XCTAssertTrue(telemetry.flush())

        let names = Set(exporter.exported.map(\.name))
        XCTAssertTrue(names.contains("endpoint_payload.bytes"))
        XCTAssertTrue(names.contains("known_tests.response_tests"))

        for metric in exporter.exported {
            XCTAssertEqual(metric.resource.telemetryDistributionNamespace, .civisibility)
        }
    }

    func testCounterIncrementsByGivenValue() throws {
        let exporter = InMemoryMetricExporter()
        let telemetry = makeTelemetry(exporter)

        telemetry.metrics.itrSkippableTests.responseTests.add(7)

        XCTAssertTrue(telemetry.flush())

        let metric = try XCTUnwrap(exporter.exported.first { $0.name == "itr_skippable_tests.response_tests" })
        let point = try XCTUnwrap(metric.data.points.first as? LongPointData)
        XCTAssertEqual(point.value, 7)
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

/// Convenience init that sets up only the OTel metric pipeline, skipping
/// app-lifecycle calls (app-started, heartbeat, app-closing). Lives here so
/// production Telemetry.swift stays free of test-only code.
extension Telemetry {
    convenience init(metricOnlyExporter exporter: MetricExporter, resource: Resource,
                     exportInterval: TimeInterval = 60)
    {
        self.init(api: NoopTelemetryApi(), telemetryExporter: nil,
                  metricExporter: exporter, resource: resource,
                  exportInterval: exportInterval)
    }
}

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
