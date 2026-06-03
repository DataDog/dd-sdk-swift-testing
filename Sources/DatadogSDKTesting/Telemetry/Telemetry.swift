/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter
internal import OpenTelemetryApi
internal import OpenTelemetrySdk

/// Common telemetry manager.
///
/// Owns a `MeterProvider` wired to the Datadog instrumentation-telemetry metric
/// pipeline and exposes every CI Visibility metric through a typed, discoverable
/// tree — e.g. `telemetry.metrics.git.command.add(command: .getRepository)`.
/// Each metric's `add` / `record` names exactly the tags it accepts. All
/// instruments are created up front in `init`.
///
/// `@unchecked Sendable`: the OTel metric storage backing each instrument is
/// internally lock-protected, so the instruments are safe to share across the
/// session/module/suite/test actors that hold this manager via `SessionConfig`.
final class Telemetry: @unchecked Sendable {
    /// Instrumentation scope (meter) name for the CI Visibility self-metrics.
    static let instrumentationScopeName = "com.datadoghq.civisibility"

    /// Typed tree of all CI Visibility telemetry metric instruments.
    let metrics: Metrics

    private let meterProvider: MeterProviderSdk

    /// - Parameters:
    ///   - exporter: where collected metric data is pushed on flush/interval.
    ///   - resource: identity (service / version / env) for the produced metrics;
    ///     the `civisibility` telemetry namespaces are stamped on a copy of it.
    ///   - exportInterval: periodic collection interval. Collection also happens
    ///     on `flush()` / `shutdown()`.
    init(exporter: MetricExporter, resource: Resource, exportInterval: TimeInterval = 60) {
        var resource = resource
        resource.telemetryMetricNamespace = .civisibility
        resource.telemetryDistributionNamespace = .civisibility

        let reader = PeriodicMetricReaderBuilder(exporter: exporter)
            .setInterval(timeInterval: exportInterval)
            .build()

        // A catch-all View must be registered for any storage to be created;
        // without it the SDK records nothing (`findViews` only consults
        // explicitly registered views, not the per-instrument defaults). The
        // default aggregation per instrument type (sum for counters, explicit
        // histogram for histograms) is what we want.
        let provider = MeterProviderSdk.builder()
            .registerView(selector: InstrumentSelectorBuilder().build(),
                          view: View.builder().build())
            .registerMetricReader(reader: reader)
            .setResource(resource: resource)
            .build()
        self.meterProvider = provider

        let meter = provider.get(name: Telemetry.instrumentationScopeName)
        self.metrics = Metrics(Factory(meter: meter))
    }

    /// Collect and export the current metric values immediately.
    @discardableResult
    func flush() -> Bool {
        meterProvider.forceFlush() == .success
    }

    /// Collect, export, and tear down the metric pipeline.
    func shutdown() {
        _ = meterProvider.shutdown()
    }
}
