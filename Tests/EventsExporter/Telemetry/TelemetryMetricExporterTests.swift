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

class TelemetryMetricExporterTests: XCTestCase {

    // MARK: - Helpers

    private func makeExporter(server: MockBackend) throws -> TelemetryMetricExporter {
        let endpoint: Endpoint = .other(testsBaseURL: server.baseURL, logsBaseURL: server.baseURL)
        let config = ExporterConfiguration.mock(performancePreset: .readAllFiles)
        let api = TelemetryApiService.mock(endpoint: endpoint)
        let storage = try Directory.temporary().createSubdirectory(path: UUID().uuidString)
        let telemetryExporter = try TelemetryExporter(config: config, storage: storage, api: api)
        return TelemetryMetricExporter(telemetryExporter: telemetryExporter)
    }

    private func receivedSeries(from server: MockBackend) throws -> [[String: Any]] {
        let raw = try XCTUnwrap(server.requests.telemetry.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [[String: Any]])
        let metricsEntry = try XCTUnwrap(payload.first(where: { $0["request_type"] as? String == "generate-metrics" }))
        let metricsPayload = try XCTUnwrap(metricsEntry["payload"] as? [String: Any])
        return try XCTUnwrap(metricsPayload["series"] as? [[String: Any]])
    }

    private func longPoint(value: Int, endNanos: UInt64,
                           attributes: [String: AttributeValue] = [:]) -> LongPointData
    {
        LongPointData(startEpochNanos: 0, endEpochNanos: endNanos,
                      attributes: attributes, exemplars: [], value: value)
    }

    private func doublePoint(value: Double, endNanos: UInt64,
                             attributes: [String: AttributeValue] = [:]) -> DoublePointData
    {
        DoublePointData(startEpochNanos: 0, endEpochNanos: endNanos,
                        attributes: attributes, exemplars: [], value: value)
    }

    private func histogramPoint(count: UInt64, sum: Double, endNanos: UInt64,
                                attributes: [String: AttributeValue] = [:]) -> HistogramPointData
    {
        HistogramPointData(startEpochNanos: 0, endEpochNanos: endNanos,
                           attributes: attributes, exemplars: [],
                           sum: sum, count: count, min: 0, max: sum,
                           boundaries: [], counts: [Int(count)], hasMin: false, hasMax: false)
    }

    // MARK: - Empty input

    func testExport_emptyMetrics_returnsSuccess() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        XCTAssertEqual(exporter.export(metrics: []), .success)
        // Allow any background flush and confirm nothing was sent.
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(server.requests.telemetry.isEmpty)
    }

    // MARK: - Gauge

    func testExport_longGauge_producesGaugeSeries() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let point = longPoint(value: 42, endNanos: 1_000_000_000)
        let metric = MetricData.createLongGauge(
            resource: Resource(),
            instrumentationScopeInfo: InstrumentationScopeInfo(name: "test"),
            name: "cpu.usage",
            description: "",
            unit: "",
            data: GaugeData(aggregationTemporality: .cumulative, points: [point])
        )

        XCTAssertEqual(exporter.export(metrics: [metric]), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let series = try receivedSeries(from: server)
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0]["metric"] as? String, "cpu.usage")
        XCTAssertEqual(series[0]["type"] as? String, "gauge")
        let points = series[0]["points"] as? [[Double]]
        XCTAssertEqual(points?.first?.last, 42.0)
    }

    func testExport_doubleGauge_producesGaugeSeries() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let point = doublePoint(value: 3.14, endNanos: 2_000_000_000)
        let metric = MetricData.createDoubleGauge(
            resource: Resource(),
            instrumentationScopeInfo: InstrumentationScopeInfo(name: "test"),
            name: "temp",
            description: "",
            unit: "",
            data: GaugeData(aggregationTemporality: .cumulative, points: [point])
        )

        XCTAssertEqual(exporter.export(metrics: [metric]), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let series = try receivedSeries(from: server)
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0]["metric"] as? String, "temp")
        XCTAssertEqual(series[0]["type"] as? String, "gauge")
        // Timestamp is endEpochNanos / 1e9 = 2.0 seconds
        let rawPoints = try XCTUnwrap(series[0]["points"] as? [[Double]])
        let firstPoint = try XCTUnwrap(rawPoints.first)
        XCTAssertEqual(firstPoint[0], 2.0, accuracy: 0.001)
        XCTAssertEqual(firstPoint[1], 3.14, accuracy: 0.001)
    }

    // MARK: - Sum (Counter)

    func testExport_monotonicSum_producesCountSeries() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let point = longPoint(value: 100, endNanos: 1_000_000_000)
        let metric = MetricData.createLongSum(
            resource: Resource(),
            instrumentationScopeInfo: InstrumentationScopeInfo(name: "test"),
            name: "requests.total",
            description: "",
            unit: "",
            isMonotonic: true,
            data: SumData(aggregationTemporality: .cumulative, points: [point])
        )

        XCTAssertEqual(exporter.export(metrics: [metric]), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let series = try receivedSeries(from: server)
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0]["metric"] as? String, "requests.total")
        XCTAssertEqual(series[0]["type"] as? String, "count")
    }

    func testExport_nonMonotonicSum_producesGaugeSeries() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let point = doublePoint(value: -5.0, endNanos: 1_000_000_000)
        let metric = MetricData.createDoubleSum(
            resource: Resource(),
            instrumentationScopeInfo: InstrumentationScopeInfo(name: "test"),
            name: "active.connections",
            description: "",
            unit: "",
            isMonotonic: false,
            data: SumData(aggregationTemporality: .cumulative, points: [point])
        )

        XCTAssertEqual(exporter.export(metrics: [metric]), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let series = try receivedSeries(from: server)
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0]["type"] as? String, "gauge")
    }

    // MARK: - Histogram

    func testExport_histogram_producesCountAndSumSeries() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let point = histogramPoint(count: 10, sum: 55.5, endNanos: 1_000_000_000)
        let metric = MetricData.createHistogram(
            resource: Resource(),
            instrumentationScopeInfo: InstrumentationScopeInfo(name: "test"),
            name: "request.duration",
            description: "",
            unit: "ms",
            data: HistogramData(aggregationTemporality: .cumulative, points: [point])
        )

        XCTAssertEqual(exporter.export(metrics: [metric]), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let series = try receivedSeries(from: server)
        XCTAssertEqual(series.count, 2)
        let names = Set(series.compactMap { $0["metric"] as? String })
        XCTAssertEqual(names, ["request.duration.count", "request.duration.sum"])

        let countSeries = try XCTUnwrap(series.first(where: { $0["metric"] as? String == "request.duration.count" }))
        XCTAssertEqual(countSeries["type"] as? String, "count")
        let countRawPoints = try XCTUnwrap(countSeries["points"] as? [[Double]])
        XCTAssertEqual(try XCTUnwrap(countRawPoints.first).last, 10.0)

        let sumSeries = try XCTUnwrap(series.first(where: { $0["metric"] as? String == "request.duration.sum" }))
        let sumRawPoints = try XCTUnwrap(sumSeries["points"] as? [[Double]])
        XCTAssertEqual(try XCTUnwrap(sumRawPoints.first).last ?? 0, 55.5, accuracy: 0.001)
    }

    // MARK: - Attributes → Tags

    func testExport_withAttributes_producesTagsInSeries() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let attributes: [String: AttributeValue] = ["env": .string("prod"), "service": .string("api")]
        let point = longPoint(value: 1, endNanos: 1_000_000_000, attributes: attributes)
        let metric = MetricData.createLongGauge(
            resource: Resource(),
            instrumentationScopeInfo: InstrumentationScopeInfo(name: "test"),
            name: "m",
            description: "",
            unit: "",
            data: GaugeData(aggregationTemporality: .cumulative, points: [point])
        )

        XCTAssertEqual(exporter.export(metrics: [metric]), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let series = try receivedSeries(from: server)
        XCTAssertEqual(series.count, 1)
        let tags = try XCTUnwrap(series[0]["tags"] as? [String])
        XCTAssertTrue(tags.contains("env:prod"))
        XCTAssertTrue(tags.contains("service:api"))
    }

    // MARK: - Multiple attribute sets → multiple series

    func testExport_multipleAttributeSets_producesMultipleSeries() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let point1 = longPoint(value: 1, endNanos: 1_000_000_000,
                               attributes: ["env": .string("prod")])
        let point2 = longPoint(value: 2, endNanos: 2_000_000_000,
                               attributes: ["env": .string("staging")])
        let metric = MetricData.createLongGauge(
            resource: Resource(),
            instrumentationScopeInfo: InstrumentationScopeInfo(name: "test"),
            name: "error.rate",
            description: "",
            unit: "",
            data: GaugeData(aggregationTemporality: .cumulative, points: [point1, point2])
        )

        XCTAssertEqual(exporter.export(metrics: [metric]), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let series = try receivedSeries(from: server)
        XCTAssertEqual(series.count, 2)
        let allTags = series.compactMap { $0["tags"] as? [String] }
        let tagStrings = allTags.flatMap { $0 }
        XCTAssertTrue(tagStrings.contains("env:prod"))
        XCTAssertTrue(tagStrings.contains("env:staging"))
    }

    // MARK: - Multiple metrics in one call

    func testExport_multipleMetrics_allSeriesForwarded() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let gauge = MetricData.createLongGauge(
            resource: Resource(),
            instrumentationScopeInfo: InstrumentationScopeInfo(name: "test"),
            name: "gauge.one",
            description: "", unit: "",
            data: GaugeData(aggregationTemporality: .cumulative,
                            points: [longPoint(value: 1, endNanos: 1_000_000_000)])
        )
        let counter = MetricData.createLongSum(
            resource: Resource(),
            instrumentationScopeInfo: InstrumentationScopeInfo(name: "test"),
            name: "counter.two",
            description: "", unit: "",
            isMonotonic: true,
            data: SumData(aggregationTemporality: .cumulative,
                          points: [longPoint(value: 2, endNanos: 1_000_000_000)])
        )

        XCTAssertEqual(exporter.export(metrics: [gauge, counter]), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let series = try receivedSeries(from: server)
        XCTAssertEqual(series.count, 2)
        let names = Set(series.compactMap { $0["metric"] as? String })
        XCTAssertEqual(names, ["gauge.one", "counter.two"])
    }

    // MARK: - Aggregation temporality

    func testGetAggregationTemporality_returnsCumulative() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        for instrument in InstrumentType.allCases {
            XCTAssertEqual(exporter.getAggregationTemporality(for: instrument), .cumulative)
        }
    }
}
