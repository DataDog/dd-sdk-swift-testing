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
/// SDK self-logs follow the same pattern: `telemetry.logs.error(...)` /
/// `.warn(...)` / `.debug(...)` accumulate in a `LogStore` (deduplicated by
/// message/level/tags with an occurrence `count`) and drain on the same timer
/// as the `logs` request type.
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
    /// Self-log handler — `telemetry.logs.error(...)` / `.warn(...)` / `.debug(...)`.
    let logs: Logs

    private let metricStore: MetricStore
    private let logStore: LogStore
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
    ///   - logCap: number of distinct buffered log entries that force an early
    ///     drain (identical logs dedup into one entry, so this counts unique logs).
    ///   - clock: time source for metric-point timestamps (the NTP-synced SDK clock).
    ///   - configuration: SDK config snapshot reported in the `app-started` payload.
    init(api: TelemetryApi,
         exporter: any TelemetryPayloadExporter,
         flushInterval: TimeInterval = 10,
         heartbeatInterval: TimeInterval = 60,
         distributionCap: Int = 65536,
         logCap: Int = 1024,
         clock: any Clock,
         configuration: [TelemetryConfigItem] = [])
    {
        let metricStore = MetricStore(exporter: exporter, distributionCap: distributionCap, clock: clock)
        let logStore = LogStore(exporter: exporter, logCap: logCap, clock: clock)
        self.metricStore = metricStore
        self.logStore = logStore
        self.exporter = exporter
        self.metrics = Metrics(Factory(store: metricStore))
        self.logs = Logs(logStore)

        // Send app-started immediately via a direct HTTP call (no batching).
        // The clock is already synced (SyncingClock.sync ran before api creation).
        let startedConfig = configuration.isEmpty ? nil : configuration
        Task.detached {
            try? await api.sendAppStarted(products: nil, configuration: startedConfig,
                                          error: nil, installSignature: nil)
        }

        let queue = DispatchQueue(label: "com.datadoghq.civisibility.telemetry",
                                  target: .global(qos: .utility))
        // Drain accumulated metrics and logs to the exporter on every interval.
        let flush = DispatchSource.makeTimerSource(queue: queue)
        flush.schedule(deadline: .now() + flushInterval, repeating: flushInterval)
        flush.setEventHandler { [weak self] in
            self?.metricStore.flush()
            self?.logStore.flush()
        }
        self.flushTimer = flush
        flush.activate()

        // Enqueue a heartbeat into the batch on every interval.
        let heartbeat = DispatchSource.makeTimerSource(queue: queue)
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

    /// Drain the accumulated metrics and logs to the exporter and push the
    /// exporter's storage towards upload immediately.
    @discardableResult
    func flush() -> Bool {
        metricStore.flush()
        logStore.flush()
        return exporter.flush()
    }

    /// Stop the timers, enqueue `app-closing`, drain a final time, and tear down
    /// the exporter — so the closing event and the last metrics ride the same batch.
    func shutdown() {
        flushTimer?.cancel()
        flushTimer = nil
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        metricStore.flush()
        logStore.flush()
        exporter.export(item: TelemetryAppClosing())
        // Synchronously upload the final batch (metrics + app-closing) before
        // tearing the worker down — otherwise it sits on disk unsent at exit.
        _ = exporter.flush()
        exporter.shutdown()
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

        private struct State {
            var counts: [Key: Int] = [:]
            var distributions: [Key: [Double]] = [:]
            var bufferedSamples = 0
        }

        private let exporter: any TelemetryPayloadExporter
        private let distributionCap: Int
        private let clock: any Clock
        private let state = Synced(State())

        init(exporter: any TelemetryPayloadExporter, distributionCap: Int, clock: any Clock) {
            self.exporter = exporter
            self.distributionCap = distributionCap
            self.clock = clock
        }

        func addCount(name: String, value: Int, tags: Set<String>) {
            state.update {
                $0.counts[Key(name: name, tags: tags), default: 0] += value
            }
        }

        func record(name: String, value: Double, tags: Set<String>) {
            let full = state.update { s -> Bool in
                s.distributions[Key(name: name, tags: tags), default: []].append(value)
                s.bufferedSamples += 1
                return s.bufferedSamples >= distributionCap
            }
            // Buffer full: drain now so the burst is persisted instead of dropped
            // or held until the timer fires. The exporter uploads it later.
            if full { flush() }
        }

        /// Atomically take and reset the buffers, then build and export the
        /// payloads outside the lock. Concurrent flushes (timer vs. force-flush)
        /// each drain a disjoint slice, so no sample is sent twice or lost.
        func flush() {
            let (counts, distributions) = state.update {
                s -> ([Key: Int], [Key: [Double]]) in
                defer { s = State() }
                return (s.counts, s.distributions)
            }

            if !counts.isEmpty {
                let now = Int64(clock.now.timeIntervalSince1970.rounded())
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

// MARK: - Log accumulation

extension Telemetry {
    /// In-memory accumulator for SDK self-logs, drained to the telemetry exporter
    /// on `flush()` as the `logs` request type.
    ///
    /// Identical logs (same message, level, tags, and stack trace) collapse into a
    /// single entry whose `count` is the number of occurrences in the interval, so
    /// a noisy repeated error costs one slot instead of many. The buffer is cleared
    /// on each drain — like `MetricStore`, a frequent flush never re-emits.
    final class LogStore: @unchecked Sendable {
        private struct Key: Hashable {
            let message: String
            let level: TelemetryLog.Level
            let tags: Set<String>
            let stackTrace: String?
        }

        private struct Entry {
            var count: Int
            /// Timestamp of the first occurrence in the current interval.
            let tracerTime: Int64
        }

        private let exporter: any TelemetryPayloadExporter
        private let logCap: Int
        private let clock: any Clock
        private let state = Synced([Key: Entry]())

        init(exporter: any TelemetryPayloadExporter, logCap: Int, clock: any Clock) {
            self.exporter = exporter
            self.logCap = logCap
            self.clock = clock
        }

        func record(message: String, level: TelemetryLog.Level, tags: Set<String>, stackTrace: String?) {
            let now = Int64(clock.now.timeIntervalSince1970)
            let full = state.update { s -> Bool in
                let key = Key(message: message, level: level, tags: tags, stackTrace: stackTrace)
                if var entry = s[key] {
                    entry.count += 1
                    s[key] = entry
                } else {
                    s[key] = Entry(count: 1, tracerTime: now)
                }
                return s.count >= logCap
            }
            // Distinct-log buffer full: drain now so the burst is persisted instead
            // of held until the timer fires. The exporter uploads it later.
            if full { flush() }
        }

        /// Atomically take and reset the buffer, then build and export the payload
        /// outside the lock. Concurrent flushes each drain a disjoint slice, so no
        /// log is sent twice or lost.
        func flush() {
            let entries = state.update { s -> [Key: Entry] in
                defer { s = [:] }
                return s
            }
            guard !entries.isEmpty else { return }

            let logs = entries.map { key, entry in
                TelemetryLog(message: key.message, level: key.level,
                             count: entry.count,
                             tags: key.tags.isEmpty ? nil : key.tags.sorted().joined(separator: ","),
                             stackTrace: key.stackTrace, tracerTime: entry.tracerTime)
            }
            exporter.export(item: TelemetryLog.Logs(logs))
        }
    }
}

// MARK: - Log handler

extension Telemetry {
    /// Typed entry point for SDK self-logs. Mirrors the metrics tree: a level per
    /// method, each accumulating into the shared `LogStore`.
    struct Logs {
        private let store: LogStore

        init(_ store: LogStore) { self.store = store }

        /// Record an error-level telemetry log.
        func error(_ message: String, tags: [String: any SpanAttributeConvertible]? = nil, stackTrace: String? = nil) {
            store.record(message: message, level: .error,
                         tags: tags?.renderTags() ?? [], stackTrace: stackTrace)
        }

        /// Record a warning-level telemetry log.
        func warn(_ message: String, tags: [String: any SpanAttributeConvertible]? = nil) {
            store.record(message: message, level: .warn,
                         tags: tags?.renderTags() ?? [], stackTrace: nil)
        }

        /// Record a debug-level telemetry log.
        func debug(_ message: String, tags: [String: any SpanAttributeConvertible]? = nil) {
            store.record(message: message, level: .debug,
                         tags: tags?.renderTags() ?? [], stackTrace: nil)
        }
    }
}
