/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

internal final class TelemetryMetricExporter: MetricExporter {
    let telemetryExporter: TelemetryExporter
    let namespace: TelemetryMetric.Namespace?
    let distributionNamespace: TelemetryDistribution.Namespace?

    init(telemetryExporter: TelemetryExporter,
         namespace: TelemetryMetric.Namespace? = nil,
         distributionNamespace: TelemetryDistribution.Namespace? = nil)
    {
        self.telemetryExporter = telemetryExporter
        self.namespace = namespace
        self.distributionNamespace = distributionNamespace
    }

    func export(metrics: [MetricData]) -> ExportResult {
        guard !metrics.isEmpty else { return .success }

        let scalarSeries = metrics.compactMap(TelemetryMetric.Series.from(_:)).flatMap { $0 }
        if !scalarSeries.isEmpty {
            telemetryExporter.export(item: TelemetryMetric(namespace: namespace, series: scalarSeries))
        }

        let distSeries = metrics.compactMap(TelemetryDistribution.Series.from(_:)).flatMap { $0 }
        if !distSeries.isEmpty {
            telemetryExporter.export(item: TelemetryDistribution(namespace: distributionNamespace, series: distSeries))
        }

        return .success
    }

    func flush() -> ExportResult {
        telemetryExporter.flush() ? .success : .failure
    }

    func shutdown() -> ExportResult {
        telemetryExporter.shutdown()
        return .success
    }

    func getAggregationTemporality(for instrument: InstrumentType) -> AggregationTemporality {
        switch instrument {
        case .upDownCounter, .observableUpDownCounter:
            // These map to a DD gauge, where the current running total is the value
            // we want to report — so keep them cumulative.
            return .cumulative
        default:
            // Counters map to DD `count` (summed per interval) and histograms map to
            // `distributions` (raw samples per interval). Both expect per-interval
            // deltas; cumulative running totals would inflate counts and re-emit the
            // full sample set on every collection. Request delta temporality.
            return .delta
        }
    }
}

// MARK: - Resource-driven configuration

internal enum TelemetryMetricResourceKeys {
    /// Resource attribute key whose value selects the telemetry namespace for the
    /// metrics / distributions produced from a meter provider. The value must match
    /// a `TelemetryMetric.Namespace` / `TelemetryDistribution.Namespace` raw value
    /// (e.g. `"tracers"`, `"general"`). When absent or unrecognized, the exporter's
    /// configured payload-level namespace is used instead.
    static let namespace = "dd.telemetry.namespace"
}

// MARK: - Shared helpers

private enum MetricConversion {
    // Per-metric namespace override read from the metric's Resource, if present.
    static func metricNamespace(from resource: Resource) -> TelemetryMetric.Namespace? {
        namespaceString(from: resource).flatMap(TelemetryMetric.Namespace.init(rawValue:))
    }

    static func distributionNamespace(from resource: Resource) -> TelemetryDistribution.Namespace? {
        namespaceString(from: resource).flatMap(TelemetryDistribution.Namespace.init(rawValue:))
    }

    private static func namespaceString(from resource: Resource) -> String? {
        resource.attributes[TelemetryMetricResourceKeys.namespace]?.description
    }

    // Group an array of PointData by their sorted attribute string so that
    // points with the same label set land in the same series.
    static func groupByAttributes<P: PointData>(_ points: [P]) -> [([String: AttributeValue], [P])] {
        var order: [String] = []
        var groups: [String: ([String: AttributeValue], [P])] = [:]
        for point in points {
            let key = tagString(point.attributes)
            if groups[key] == nil {
                order.append(key)
                groups[key] = (point.attributes, [])
            }
            groups[key]!.1.append(point)
        }
        return order.map { groups[$0]! }
    }

    static func epochSeconds(_ point: PointData) -> TimeInterval {
        TimeInterval(point.endEpochNanos) / 1_000_000_000
    }

    static func scalarValue(_ point: PointData) -> Double {
        if let p = point as? LongPointData { return Double(p.value) }
        if let p = point as? DoublePointData { return p.value }
        return 0
    }

    static func tags(_ attributes: [String: AttributeValue]) -> [String]? {
        guard !attributes.isEmpty else { return nil }
        return attributes.map { "\($0.key):\($0.value.description)" }.sorted()
    }

    static func tagString(_ attributes: [String: AttributeValue]) -> String {
        tags(attributes)?.joined(separator: ",") ?? ""
    }
}

// MARK: - MetricData → TelemetryMetric.Series (gauge / sum / summary)

private extension TelemetryMetric.Series {
    // Returns nil for histogram types — those go to TelemetryDistribution instead.
    static func from(_ metric: MetricData) -> [TelemetryMetric.Series]? {
        let namespace = MetricConversion.metricNamespace(from: metric.resource)
        switch metric.type {
        case .LongGauge, .DoubleGauge:
            return scalar(metric.data.points, name: metric.name, type: .gauge, namespace: namespace)
        case .LongSum, .DoubleSum:
            return scalar(metric.data.points, name: metric.name,
                         type: metric.isMonotonic ? .count : .gauge, namespace: namespace)
        case .Summary:
            return countAndSum(metric.data.points as! [SummaryPointData],
                               name: metric.name,
                               namespace: namespace,
                               countOf: { Double($0.count) },
                               sumOf: { $0.sum })
        case .Histogram, .ExponentialHistogram:
            return nil
        }
    }

    private static func scalar(_ points: [PointData], name: String,
                               type: TelemetryMetric.MetricType,
                               namespace: TelemetryMetric.Namespace?) -> [TelemetryMetric.Series]
    {
        MetricConversion.groupByAttributes(points).map { attrs, pts in
            TelemetryMetric.Series(
                metric: name,
                points: pts.map { .init(timestamp: MetricConversion.epochSeconds($0),
                                        value: MetricConversion.scalarValue($0)) },
                type: type,
                tags: MetricConversion.tags(attrs),
                namespace: namespace
            )
        }
    }

    // Summary emits {name}.count and {name}.sum as generate-metrics (already aggregated).
    private static func countAndSum<P: PointData>(
        _ points: [P],
        name: String,
        namespace: TelemetryMetric.Namespace?,
        countOf: (P) -> Double,
        sumOf: (P) -> Double
    ) -> [TelemetryMetric.Series] {
        MetricConversion.groupByAttributes(points).flatMap { attrs, pts -> [TelemetryMetric.Series] in
            let tags = MetricConversion.tags(attrs)
            return [
                TelemetryMetric.Series(
                    metric: "\(name).count",
                    points: pts.map { .init(timestamp: MetricConversion.epochSeconds($0), value: countOf($0)) },
                    type: .count,
                    tags: tags,
                    namespace: namespace
                ),
                TelemetryMetric.Series(
                    metric: "\(name).sum",
                    points: pts.map { .init(timestamp: MetricConversion.epochSeconds($0), value: sumOf($0)) },
                    type: .count,
                    tags: tags,
                    namespace: namespace
                ),
            ]
        }
    }
}

// MARK: - MetricData → TelemetryDistribution.Series (histogram types)

private extension TelemetryDistribution.Series {
    // Returns nil for non-histogram types.
    static func from(_ metric: MetricData) -> [TelemetryDistribution.Series]? {
        let namespace = MetricConversion.distributionNamespace(from: metric.resource)
        switch metric.type {
        case .Histogram:
            return fromHistogram(metric.data.points as! [HistogramPointData],
                                 name: metric.name, namespace: namespace)
        case .ExponentialHistogram:
            return fromExponentialHistogram(metric.data.points as! [ExponentialHistogramPointData],
                                            name: metric.name, namespace: namespace)
        default:
            return nil
        }
    }

    // Reconstruct approximate sample values from explicit-boundary histogram buckets.
    // For each bucket, the representative value is:
    //   - underflow (first) bucket: min if available, else the first boundary
    //   - interior buckets: midpoint of the two boundaries
    //   - overflow (last) bucket: max if available, else the upper boundary
    private static func fromHistogram(_ points: [HistogramPointData],
                                      name: String,
                                      namespace: TelemetryDistribution.Namespace?) -> [TelemetryDistribution.Series]
    {
        MetricConversion.groupByAttributes(points).compactMap { attrs, pts -> TelemetryDistribution.Series? in
            let samples = pts.flatMap { reconstructSamples(from: $0) }
            guard !samples.isEmpty else { return nil }
            return TelemetryDistribution.Series(
                metric: name,
                points: samples,
                tags: MetricConversion.tags(attrs),
                namespace: namespace
            )
        }
    }

    private static func reconstructSamples(from point: HistogramPointData) -> [Double] {
        guard point.count > 0 else { return [] }
        let boundaries = point.boundaries
        let counts = point.counts

        // No boundaries: use sum/count as a single representative value repeated count times.
        guard !boundaries.isEmpty else {
            let avg = point.count > 0 ? point.sum / Double(point.count) : 0
            return Array(repeating: avg, count: Int(point.count))
        }

        var samples: [Double] = []
        for (i, count) in counts.enumerated() {
            guard count > 0 else { continue }
            let midpoint: Double
            if i == 0 {
                midpoint = point.hasMin ? point.min : boundaries[0]
            } else if i == boundaries.count {
                midpoint = point.hasMax ? point.max : boundaries[boundaries.count - 1]
            } else {
                midpoint = (boundaries[i - 1] + boundaries[i]) / 2
            }
            samples.append(contentsOf: Array(repeating: midpoint, count: count))
        }
        return samples
    }

    // Reconstruct approximate sample values from exponential-bucket histogram points.
    // Base = 2^(2^-scale); each bucket i covers [base^(offset+i), base^(offset+i+1)).
    // Representative value: geometric midpoint = base^(offset+i+0.5).
    private static func fromExponentialHistogram(_ points: [ExponentialHistogramPointData],
                                                 name: String,
                                                 namespace: TelemetryDistribution.Namespace?) -> [TelemetryDistribution.Series]
    {
        MetricConversion.groupByAttributes(points).compactMap { attrs, pts -> TelemetryDistribution.Series? in
            let samples = pts.flatMap { reconstructSamples(from: $0) }
            guard !samples.isEmpty else { return nil }
            return TelemetryDistribution.Series(
                metric: name,
                points: samples,
                tags: MetricConversion.tags(attrs),
                namespace: namespace
            )
        }
    }

    private static func reconstructSamples(from point: ExponentialHistogramPointData) -> [Double] {
        guard point.count > 0 else { return [] }
        // base = 2^(2^-scale)
        let base = pow(2.0, pow(2.0, Double(-point.scale)))
        var samples: [Double] = []

        if point.zeroCount > 0 {
            samples.append(contentsOf: Array(repeating: 0.0, count: Int(point.zeroCount)))
        }
        for (i, count) in point.positiveBuckets.bucketCounts.enumerated() {
            guard count > 0 else { continue }
            let exp = Double(point.positiveBuckets.offset + i) + 0.5
            samples.append(contentsOf: Array(repeating: pow(base, exp), count: Int(count)))
        }
        for (i, count) in point.negativeBuckets.bucketCounts.enumerated() {
            guard count > 0 else { continue }
            let exp = Double(point.negativeBuckets.offset + i) + 0.5
            samples.append(contentsOf: Array(repeating: -pow(base, exp), count: Int(count)))
        }
        return samples
    }
}
