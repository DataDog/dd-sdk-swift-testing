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
        Telemetry(exporter: exporter, resource: Resource(), exportInterval: 3600)
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
}
