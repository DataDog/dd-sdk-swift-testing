/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

/// Common telemetry manager.
///
/// Collects the SDK's CI Visibility self-metrics and periodically writes them to
/// the durable telemetry exporter. Metrics are exposed through a typed,
/// discoverable tree — e.g. `telemetry.metrics.git.command.add(command: .getRepository)`.
/// Each metric's `add` / `record` names exactly the tags it accepts. All
/// instruments are created up front in `init`.
///
/// Counters and distributions are accumulated in memory (`MetricStore`) and
/// drained on a short interval. Because the exporter persists every drained
/// payload to disk before uploading on its own schedule, a frequent flush keeps
/// the window of metrics lost to a crash small; the only data at risk is what
/// has accumulated since the last flush.
///
/// Also drives the app-lifecycle telemetry protocol:
/// - Sends `app-started` directly (no batching) right after init.
/// - Enqueues `app-heartbeat` via the exporter on a repeating timer.
/// - Enqueues `app-closing` into the last batch on `shutdown()` so it is flushed
///   together with the final metric drain.
///
/// `@unchecked Sendable`: `MetricStore` is internally lock-protected, so the
/// instruments are safe to share across the session/module/suite/test actors
/// that hold this manager via `SessionConfig`.
final class Telemetry: @unchecked Sendable {
    /// Typed tree of all CI Visibility telemetry metric instruments.
    let metrics: Metrics

    private let store: MetricStore
    private let exporter: any TelemetryPayloadExporter
    private var flushTimer: (any DispatchSourceTimer)?
    private var heartbeatTimer: (any DispatchSourceTimer)?

    /// - Parameters:
    ///   - api: direct telemetry API used for the unbatched `app-started` call.
    ///   - exporter: durable telemetry queue drained metrics, heartbeats, and the
    ///     closing event are written to.
    ///   - flushInterval: metric drain cadence, in seconds. Kept short so a crash
    ///     loses at most one interval of metrics.
    ///   - heartbeatInterval: `app-heartbeat` period, in seconds.
    ///   - distributionCap: total buffered distribution samples that force an
    ///     early drain (so a burst is persisted rather than waiting for the timer).
    ///   - configuration: SDK config snapshot reported in the `app-started` payload.
    init(api: TelemetryApi,
         exporter: any TelemetryPayloadExporter,
         flushInterval: TimeInterval = 10,
         heartbeatInterval: TimeInterval = 60,
         distributionCap: Int = 2048,
         configuration: [TelemetryConfigItem] = [])
    {
        let store = MetricStore(exporter: exporter, distributionCap: distributionCap)
        self.store = store
        self.exporter = exporter
        self.metrics = Metrics(Factory(store: store))

        // Send app-started immediately via a direct HTTP call (no batching).
        // The clock is already synced (SyncingClock.sync ran before api creation).
        let startedConfig = configuration.isEmpty ? nil : configuration
        Task.detached {
            try? await api.sendAppStarted(products: nil, configuration: startedConfig,
                                          error: nil, installSignature: nil)
        }

        // Drain accumulated metrics to the exporter on every interval.
        let flush = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "com.datadoghq.civisibility.telemetry"))
        flush.schedule(deadline: .now() + flushInterval, repeating: flushInterval)
        flush.setEventHandler { [weak self] in self?.store.flush() }
        self.flushTimer = flush
        flush.activate()

        // Enqueue a heartbeat into the batch on every interval.
        let heartbeat = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        heartbeat.schedule(deadline: .now() + heartbeatInterval, repeating: heartbeatInterval)
        heartbeat.setEventHandler { [weak self] in
            self?.exporter.export(item: TelemetryAppHeartbeat())
        }
        self.heartbeatTimer = heartbeat
        heartbeat.activate()
    }

    deinit {
        flushTimer?.cancel()
        heartbeatTimer?.cancel()
    }

    /// Drain the accumulated metrics to the exporter and push the exporter's
    /// storage towards upload immediately.
    @discardableResult
    func flush() -> Bool {
        store.flush()
        return exporter.flush()
    }

    /// Stop the timers, enqueue `app-closing`, drain a final time, and tear down
    /// the exporter — so the closing event and the last metrics ride the same batch.
    func shutdown() {
        flushTimer?.cancel()
        flushTimer = nil
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        store.flush()
        exporter.export(item: TelemetryAppClosing())
        exporter.shutdown()
    }

    /// Render a typed tag set to the `"key:value"` wire form as a `Set`, so a
    /// given label set maps to a single series regardless of order (`Set`
    /// equality/hashing is order-independent). The wire array is sorted once at
    /// emit time.
    static func renderTags(_ tags: Tags) -> Set<String> {
        Set(tags.map { "\($0.key):\($0.value.spanAttribute)" })
    }
}

// MARK: - Metric accumulation

extension Telemetry {
    /// In-memory accumulator for counters and distributions, drained to the
    /// telemetry exporter on `flush()`.
    ///
    /// Counters keep a running per-interval delta (the backend sums deltas);
    /// distributions keep every raw sample (the backend computes the statistical
    /// summary). Both are cleared on each drain — delta semantics — so a frequent
    /// flush never re-emits already-reported data.
    final class MetricStore: @unchecked Sendable {
        private struct Key: Hashable {
            let name: String
            let tags: Set<String>
        }

        private let exporter: any TelemetryPayloadExporter
        private let distributionCap: Int
        private let lock = UnfairLock()

        private var counts: [Key: Int] = [:]
        private var distributions: [Key: [Double]] = [:]
        private var bufferedSamples = 0

        init(exporter: any TelemetryPayloadExporter, distributionCap: Int) {
            self.exporter = exporter
            self.distributionCap = distributionCap
        }

        func addCount(name: String, value: Int, tags: Set<String>) {
            lock.whileLocked {
                counts[Key(name: name, tags: tags), default: 0] += value
            }
        }

        func record(name: String, value: Double, tags: Set<String>) {
            let full = lock.whileLocked { () -> Bool in
                distributions[Key(name: name, tags: tags), default: []].append(value)
                bufferedSamples += 1
                return bufferedSamples >= distributionCap
            }
            // Buffer full: drain now so the burst is persisted instead of dropped
            // or held until the timer fires. The exporter uploads it later.
            if full { flush() }
        }

        /// Atomically take and reset the buffers, then build and export the
        /// payloads outside the lock. Concurrent flushes (timer vs. force-flush)
        /// each drain a disjoint slice, so no sample is sent twice or lost.
        func flush() {
            let (counts, distributions) = lock.whileLocked {
                () -> ([Key: Int], [Key: [Double]]) in
                defer {
                    self.counts = [:]
                    self.distributions = [:]
                    self.bufferedSamples = 0
                }
                return (self.counts, self.distributions)
            }

            if !counts.isEmpty {
                let now = Date().timeIntervalSince1970
                let series = counts.map { key, value in
                    TelemetryMetric.Series(
                        metric: key.name,
                        points: [.init(timestamp: now, value: Double(value))],
                        type: .count,
                        tags: key.tags.isEmpty ? nil : key.tags.sorted()
                    )
                }
                exporter.export(item: TelemetryMetric(namespace: .civisibility, series: series))
            }

            if !distributions.isEmpty {
                let series = distributions.map { key, points in
                    TelemetryDistribution.Series(
                        metric: key.name,
                        points: points,
                        tags: key.tags.isEmpty ? nil : key.tags.sorted()
                    )
                }
                exporter.export(item: TelemetryDistribution(namespace: .civisibility, series: series))
            }
        }
    }
}
