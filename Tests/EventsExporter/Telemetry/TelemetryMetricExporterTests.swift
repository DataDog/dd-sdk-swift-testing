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
                                boundaries: [Double] = [],
                                counts: [Int]? = nil,
                                min: Double = 0, max: Double = 0,
                                hasMin: Bool = false, hasMax: Bool = false,
                                attributes: [String: AttributeValue] = [:]) -> HistogramPointData
    {
        let bucketCounts = counts ?? [Int(count)]
        return HistogramPointData(startEpochNanos: 0, endEpochNanos: endNanos,
                                  attributes: attributes, exemplars: [],
                                  sum: sum, count: count, min: min, max: max,
                                  boundaries: boundaries, counts: bucketCounts,
                                  hasMin: hasMin, hasMax: hasMax)
    }

    private func receivedDistSeries(from server: MockBackend) throws -> [[String: Any]] {
        let raw = try XCTUnwrap(server.requests.telemetry.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [[String: Any]])
        let distEntry = try XCTUnwrap(payload.first(where: { $0["request_type"] as? String == "distributions" }))
        let distPayload = try XCTUnwrap(distEntry["payload"] as? [String: Any])
        return try XCTUnwrap(distPayload["series"] as? [[String: Any]])
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

    // MARK: - Histogram → distributions

    func testExport_histogram_noBoundaries_producesDistributionSeriesWithAvgRepeated() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        // No boundaries: 4 samples, sum=10 → avg=2.5 repeated 4 times
        let point = histogramPoint(count: 4, sum: 10, endNanos: 1_000_000_000,
                                   boundaries: [], counts: [4])
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

        let series = try receivedDistSeries(from: server)
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0]["metric"] as? String, "request.duration")
        let points = try XCTUnwrap(series[0]["points"] as? [Double])
        XCTAssertEqual(points.count, 4)
        XCTAssertEqual(points[0], 2.5, accuracy: 0.001)
    }

    func testExport_histogram_withBoundaries_reconstructsSamplesFromMidpoints() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        // Boundaries [0, 10, 100], counts [1, 2, 3, 1]:
        //   bucket 0 (underflow, hasMin=true, min=0): 1 sample → 0.0
        //   bucket 1 [0,10): midpoint 5.0: 2 samples
        //   bucket 2 [10,100): midpoint 55.0: 3 samples
        //   bucket 3 (overflow, hasMax=true, max=120): 1 sample → 120.0
        let point = histogramPoint(count: 7, sum: 0, endNanos: 1_000_000_000,
                                   boundaries: [0, 10, 100], counts: [1, 2, 3, 1],
                                   min: 0, max: 120, hasMin: true, hasMax: true)
        let metric = MetricData.createHistogram(
            resource: Resource(),
            instrumentationScopeInfo: InstrumentationScopeInfo(name: "test"),
            name: "latency",
            description: "",
            unit: "ms",
            data: HistogramData(aggregationTemporality: .cumulative, points: [point])
        )

        XCTAssertEqual(exporter.export(metrics: [metric]), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let series = try receivedDistSeries(from: server)
        XCTAssertEqual(series.count, 1)
        let points = try XCTUnwrap(series[0]["points"] as? [Double])
        XCTAssertEqual(points.count, 7)
        XCTAssertEqual(points[0], 0.0, accuracy: 0.001)   // underflow → min
        XCTAssertEqual(points[1], 5.0, accuracy: 0.001)   // bucket [0,10) midpoint
        XCTAssertEqual(points[2], 5.0, accuracy: 0.001)
        XCTAssertEqual(points[3], 55.0, accuracy: 0.001)  // bucket [10,100) midpoint
        XCTAssertEqual(points[4], 55.0, accuracy: 0.001)
        XCTAssertEqual(points[5], 55.0, accuracy: 0.001)
        XCTAssertEqual(points[6], 120.0, accuracy: 0.001) // overflow → max
    }

    func testExport_histogram_noMinMax_fallsBackToBoundaries() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        // Boundaries [10, 100], counts [1, 1, 1], no min/max available:
        //   bucket 0 (underflow, no min): falls back to first boundary → 10.0
        //   bucket 1 [10,100): midpoint 55.0
        //   bucket 2 (overflow, no max): falls back to last boundary → 100.0
        let point = histogramPoint(count: 3, sum: 0, endNanos: 1_000_000_000,
                                   boundaries: [10, 100], counts: [1, 1, 1],
                                   hasMin: false, hasMax: false)
        let metric = MetricData.createHistogram(
            resource: Resource(),
            instrumentationScopeInfo: InstrumentationScopeInfo(name: "test"),
            name: "latency",
            description: "",
            unit: "ms",
            data: HistogramData(aggregationTemporality: .cumulative, points: [point])
        )

        XCTAssertEqual(exporter.export(metrics: [metric]), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let series = try receivedDistSeries(from: server)
        XCTAssertEqual(series.count, 1)
        let points = try XCTUnwrap(series[0]["points"] as? [Double])
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0], 10.0, accuracy: 0.001)  // underflow → first boundary
        XCTAssertEqual(points[1], 55.0, accuracy: 0.001)  // [10,100) midpoint
        XCTAssertEqual(points[2], 100.0, accuracy: 0.001) // overflow → last boundary
    }

    func testExport_histogram_doesNotProduceGenerateMetricsSeries() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        let point = histogramPoint(count: 3, sum: 9, endNanos: 1_000_000_000)
        let metric = MetricData.createHistogram(
            resource: Resource(),
            instrumentationScopeInfo: InstrumentationScopeInfo(name: "test"),
            name: "h",
            description: "",
            unit: "",
            data: HistogramData(aggregationTemporality: .cumulative, points: [point])
        )

        XCTAssertEqual(exporter.export(metrics: [metric]), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let raw = try XCTUnwrap(server.requests.telemetry.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [[String: Any]])
        let hasMetrics = payload.contains(where: { $0["request_type"] as? String == "generate-metrics" })
        XCTAssertFalse(hasMetrics, "Histogram must not produce generate-metrics entries")
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

    // MARK: - Namespace from Resource

    func testExport_resourceNamespace_setsPerSeriesNamespace() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        var resource = Resource(attributes: [:])
        resource.telemetryNamespace = "general"
        let metric = MetricData.createLongGauge(
            resource: resource,
            instrumentationScopeInfo: InstrumentationScopeInfo(name: "test"),
            name: "m",
            description: "",
            unit: "",
            data: GaugeData(aggregationTemporality: .cumulative,
                            points: [longPoint(value: 1, endNanos: 1_000_000_000)])
        )

        XCTAssertEqual(exporter.export(metrics: [metric]), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let series = try receivedSeries(from: server)
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0]["namespace"] as? String, "general")
    }

    func testExport_resourceNamespace_setsDistributionSeriesNamespace() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        var resource = Resource(attributes: [:])
        resource.telemetryNamespace = "appsec"
        let point = histogramPoint(count: 2, sum: 4, endNanos: 1_000_000_000)
        let metric = MetricData.createHistogram(
            resource: resource,
            instrumentationScopeInfo: InstrumentationScopeInfo(name: "test"),
            name: "h",
            description: "",
            unit: "",
            data: HistogramData(aggregationTemporality: .cumulative, points: [point])
        )

        XCTAssertEqual(exporter.export(metrics: [metric]), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let series = try receivedDistSeries(from: server)
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0]["namespace"] as? String, "appsec")
    }

    func testExport_unrecognizedResourceNamespace_omitsSeriesNamespace() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        var resource = Resource(attributes: [:])
        resource.telemetryNamespace = "not-a-namespace"
        let metric = MetricData.createLongGauge(
            resource: resource,
            instrumentationScopeInfo: InstrumentationScopeInfo(name: "test"),
            name: "m",
            description: "",
            unit: "",
            data: GaugeData(aggregationTemporality: .cumulative,
                            points: [longPoint(value: 1, endNanos: 1_000_000_000)])
        )

        XCTAssertEqual(exporter.export(metrics: [metric]), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let series = try receivedSeries(from: server)
        XCTAssertEqual(series.count, 1)
        XCTAssertNil(series[0]["namespace"], "Unrecognized namespace should fall back (no per-series override)")
    }

    func testExport_distributionRejectsMetricOnlyNamespace() throws {
        // "general" is valid for generate-metrics but not for distributions.
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        var resource = Resource(attributes: [:])
        resource.telemetryNamespace = "general"
        let point = histogramPoint(count: 1, sum: 1, endNanos: 1_000_000_000)
        let metric = MetricData.createHistogram(
            resource: resource,
            instrumentationScopeInfo: InstrumentationScopeInfo(name: "test"),
            name: "h",
            description: "",
            unit: "",
            data: HistogramData(aggregationTemporality: .cumulative, points: [point])
        )

        XCTAssertEqual(exporter.export(metrics: [metric]), .success)
        guard server.waitForTelemetry(timeout: 10) else { XCTFail("No telemetry received"); return }

        let series = try receivedDistSeries(from: server)
        XCTAssertEqual(series.count, 1)
        XCTAssertNil(series[0]["namespace"], "Namespace not valid for distributions should be omitted")
    }

    // MARK: - Aggregation temporality

    func testGetAggregationTemporality_deltaForCountersAndHistograms() throws {
        let server = MockBackend()
        try server.start()
        defer { server.stop() }

        let exporter = try makeExporter(server: server)
        // Up/down counters → DD gauge: keep cumulative (current running total).
        XCTAssertEqual(exporter.getAggregationTemporality(for: .upDownCounter), .cumulative)
        XCTAssertEqual(exporter.getAggregationTemporality(for: .observableUpDownCounter), .cumulative)
        // Everything else → DD count / distributions: per-interval delta.
        for instrument in [InstrumentType.counter, .observableCounter, .histogram, .gauge, .observableGauge] {
            XCTAssertEqual(exporter.getAggregationTemporality(for: instrument), .delta)
        }
    }
}
