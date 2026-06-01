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

    init(telemetryExporter: TelemetryExporter, namespace: TelemetryMetric.Namespace? = nil) {
        self.telemetryExporter = telemetryExporter
        self.namespace = namespace
    }

    func export(metrics: [MetricData]) -> ExportResult {
        guard !metrics.isEmpty else { return .success }
        let series = metrics.flatMap { TelemetryMetric.Series.from($0) }
        guard !series.isEmpty else { return .success }
        telemetryExporter.export(item: TelemetryMetric(namespace: namespace, series: series))
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
        .cumulative
    }
}

// MARK: - MetricData → TelemetryMetric.Series conversion

private extension TelemetryMetric.Series {
    static func from(_ metric: MetricData) -> [TelemetryMetric.Series] {
        switch metric.type {
        case .LongGauge, .DoubleGauge:
            return scalar(metric.data.points, name: metric.name, type: .gauge)
        case .LongSum, .DoubleSum:
            return scalar(metric.data.points, name: metric.name,
                         type: metric.isMonotonic ? .count : .gauge)
        case .Histogram:
            return countAndSum(metric.data.points as! [HistogramPointData],
                               name: metric.name,
                               countOf: { Double($0.count) },
                               sumOf: { $0.sum })
        case .ExponentialHistogram:
            return countAndSum(metric.data.points as! [ExponentialHistogramPointData],
                               name: metric.name,
                               countOf: { Double($0.count) },
                               sumOf: { $0.sum })
        case .Summary:
            return countAndSum(metric.data.points as! [SummaryPointData],
                               name: metric.name,
                               countOf: { Double($0.count) },
                               sumOf: { $0.sum })
        }
    }

    // One series per distinct attribute set, each carrying all matching points.
    private static func scalar(_ points: [PointData], name: String,
                               type: TelemetryMetric.MetricType) -> [TelemetryMetric.Series]
    {
        groupByAttributes(points).map { attrs, pts in
            TelemetryMetric.Series(
                metric: name,
                points: pts.map { .init(timestamp: epochSeconds($0), value: scalarValue($0)) },
                type: type,
                tags: tags(attrs)
            )
        }
    }

    // Histogram-like types emit a `{name}.count` and `{name}.sum` series per attribute set.
    private static func countAndSum<P: PointData>(
        _ points: [P],
        name: String,
        countOf: (P) -> Double,
        sumOf: (P) -> Double
    ) -> [TelemetryMetric.Series] {
        groupByAttributes(points).flatMap { attrs, pts -> [TelemetryMetric.Series] in
            let tags = tags(attrs)
            return [
                TelemetryMetric.Series(
                    metric: "\(name).count",
                    points: pts.map { .init(timestamp: epochSeconds($0), value: countOf($0)) },
                    type: .count,
                    tags: tags
                ),
                TelemetryMetric.Series(
                    metric: "\(name).sum",
                    points: pts.map { .init(timestamp: epochSeconds($0), value: sumOf($0)) },
                    type: .count,
                    tags: tags
                ),
            ]
        }
    }

    // Group an array of PointData by their sorted attribute string so that
    // points with the same label set land in the same series.
    private static func groupByAttributes<P: PointData>(_ points: [P]) -> [([String: AttributeValue], [P])] {
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

    private static func epochSeconds(_ point: PointData) -> TimeInterval {
        TimeInterval(point.endEpochNanos) / 1_000_000_000
    }

    private static func scalarValue(_ point: PointData) -> Double {
        if let p = point as? LongPointData { return Double(p.value) }
        if let p = point as? DoublePointData { return p.value }
        return 0
    }

    private static func tags(_ attributes: [String: AttributeValue]) -> [String]? {
        guard !attributes.isEmpty else { return nil }
        return attributes.map { "\($0.key):\($0.value.description)" }.sorted()
    }

    private static func tagString(_ attributes: [String: AttributeValue]) -> String {
        tags(attributes)?.joined(separator: ",") ?? ""
    }
}
