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
/// Also drives the app-lifecycle telemetry protocol:
/// - Sends `app-started` directly (no batching) right after init.
/// - Enqueues `app-heartbeat` via `TelemetryExporter` on a repeating timer.
/// - Enqueues `app-closing` into the last batch just before shutdown so it is
///   flushed together with the final metric collection.
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
    private let telemetryExporter: TelemetryExporter
    private var heartbeatSource: (any DispatchSourceTimer)?

    /// - Parameters:
    ///   - api: direct telemetry API used for the unbatched `app-started` call.
    ///   - telemetryExporter: batch storage used for heartbeats, `app-closing`,
    ///     and metric series.
    ///   - metricExporter: OTel-side exporter bridging meter data to the batch.
    ///   - resource: identity (service / version / env) for the produced metrics.
    ///   - exportInterval: periodic collection interval and heartbeat period.
    init(api: TelemetryApi, telemetryExporter: TelemetryExporter,
         metricExporter: MetricExporter, resource: Resource,
         exportInterval: TimeInterval = 60,
         configuration: [TelemetryConfigItem] = [])
    {
        var resource = resource
        resource.telemetryMetricNamespace = .civisibility
        resource.telemetryDistributionNamespace = .civisibility

        let reader = PeriodicMetricReaderBuilder(exporter: metricExporter)
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
        self.telemetryExporter = telemetryExporter

        let meter = provider.get(name: Telemetry.instrumentationScopeName)
        self.metrics = Metrics(Factory(meter: meter))

        // Send app-started immediately via a direct HTTP call (no batching).
        let startedConfig = configuration.isEmpty ? nil : configuration
        Task.detached {
            try? await api.sendAppStarted(products: nil, configuration: startedConfig,
                                          error: nil, installSignature: nil)
        }

        // Enqueue a heartbeat into the batch on every export interval.
        let source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        source.schedule(deadline: .now() + exportInterval, repeating: exportInterval)
        source.setEventHandler { [weak self] in
            self?.telemetryExporter.export(item: TelemetryAppHeartbeat())
        }
        source.resume()
        self.heartbeatSource = source
    }

    /// Collect and export the current metric values immediately.
    @discardableResult
    func flush() -> Bool {
        meterProvider.forceFlush() == .success
    }

    /// Enqueue `app-closing` into the current batch, then collect and export
    /// the final metric snapshot and tear down the pipeline.
    func shutdown() {
        heartbeatSource?.cancel()
        heartbeatSource = nil
        telemetryExporter.export(item: TelemetryAppClosing())
        _ = meterProvider.shutdown()
    }
}
