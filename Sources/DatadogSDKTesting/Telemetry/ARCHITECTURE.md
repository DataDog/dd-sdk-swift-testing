# Telemetry architecture

SDK self-telemetry (CI Visibility "instrumentation telemetry" metrics). This
document explains how the pieces fit together and what is intentionally left
for **SDTEST-3777** (gather the remaining metrics).

Milestone history:
- **SDTEST-3775** — the metric instances + the common `Telemetry` manager.
- **SDTEST-3776** — wiring: observer hooks in `EventsExporter`, `Telemetry`
  created with the tracer, request/upload/payload metrics gathered.
- **SDTEST-3777** — gather the remaining (local + response-count) metrics.

---

## 1. Big picture

```
                       DatadogSDKTesting (high level)                EventsExporter (low level)
                       ─────────────────────────────                ──────────────────────────
 features ── record ─▶ Telemetry.metrics.<group>.<metric>
   (events, git cmd,        │  (typed tree, 59 metrics)
    itr, coverage…)         │
                            ▼
                       MeterProviderSdk ──▶ PeriodicMetricReader ──▶ TelemetryMetricExporter
                       (OpenTelemetry)        (heartbeat)              (OTel MetricData ──▶ DD)
                                                                          │
                                                                          ▼
                                                                     TelemetryExporter
                                                                     (batch + upload via
                                                                      api.telemetry)

 exporter/network internals report neutral facts back UP via observer protocols:
   HTTPClient / DataUploadWorker / FileWriter ── RequestObserver / UploadObserver / PayloadObserver
        │                                                          │
        └──────────── observers are adapters that call ───────────▶ Telemetry.metrics.<group>.<metric>
```

Two rules drive the whole design:

1. **`EventsExporter` is the lower module** — it cannot import `Telemetry`
   (which lives in `DatadogSDKTesting`). So metrics emitted deep in the
   network/storage layer are reported via **neutral observer protocols** defined
   in `EventsExporter`; the `Telemetry`-aware adapters live in
   `DatadogSDKTesting`. (Dependency inversion, modelled on the existing `Logger`
   protocol.)
2. **Metric identity/tags stay next to the metric tree** — `EventsExporter` only
   reports facts (durations, byte sizes, status codes, counts). Which metric and
   which tags they map to is decided in `DatadogSDKTesting`.

---

## 2. The metric tree (SDTEST-3775)

`Telemetry` (`Telemetry.swift`) owns an OpenTelemetry `MeterProviderSdk` wired to
`TelemetryMetricExporter` through a `PeriodicMetricReader`. It exposes every CI
Visibility metric through a typed, discoverable tree:

```swift
telemetry.metrics.git.command.add(command: .getRepository)
telemetry.metrics.endpointPayload.requestsErrors.add(errorType: .timeout, endpoint: .testCycle)
telemetry.metrics.events.created.add(testFramework: "XCTest", eventType: .test)
telemetry.metrics.knownTests.responseTests.record(42)
```

Files:
- `TelemetryMetrics.swift` — the tree: `Telemetry.Metrics` → groups (`events`,
  `session`, `codeCoverage`, `endpointPayload`, `git`, `gitRequests`, `itr`,
  `itrSkippableTests`, `knownTests`, `testManagementTests`, `impactedTests`) →
  per-metric structs. Also the low-level `Counter` / `Distribution` handles and
  the `Factory` that builds instruments from the meter.
- `TelemetryTags.swift` — typed tag-value enums (`EventType`, `Endpoint`,
  `ErrorType`, `GitCommand`, `RetryReason`, `ShaProvider`, …), conforming to
  `SpanAttributeConvertible` (so `Bool`/`Int`/enum → wire string uniformly).
- `Telemetry.swift` — the manager, the meter provider, `flush()` / `shutdown()`.

Metric set = union of the CSV spec and `dd-trace-go` (37 counters + 22
distributions), all under the `civisibility` telemetry namespace.

### Gotchas
- **A catch-all `View` must be registered** on the meter provider or the SDK
  records nothing (`findViews` only consults explicitly-registered views, not the
  per-instrument defaults). See `Telemetry.init`.
- `civisibility` had to be added to `TelemetryMetric.Namespace` /
  `TelemetryDistribution.Namespace` in `EventsExporter`.
- `TelemetryMetricExporter.getAggregationTemporality` returns **delta** for
  counters/histograms and **cumulative** for up-down counters.

---

## 3. Lifecycle / wiring (SDTEST-3776)

- `Telemetry` is created **inside `DDTracer`** (convenience init), right after the
  API client and **before** the `Exporter` — so the exporter can be handed the
  telemetry observers, and so the feature factories can reach it. See
  `DDTracer.makeTelemetry(...)`.
- Gated by `DD_INSTRUMENTATION_TELEMETRY_ENABLED` (default `true`). Heartbeat /
  export interval is `DD_TELEMETRY_HEARTBEAT_INTERVAL` (seconds, clamped 1…3600,
  default 60).
- Exposed as `DDTracer.telemetry`; `SessionConfig.telemetry` is sourced from it
  (so `DDSession`/`Module`/`Suite`/`Test` and observers all share one instance).
- The exporter + telemetry share a single `ExporterConfiguration` on the
  **default** performance preset (changed from `.instantDataDelivery` in 3776).

---

## 4. Observer hooks (the cross-module bridge)

Defined in `EventsExporter/Telemetry/MetricObservers.swift` (neutral, public):

| Protocol | Reported from | Carries |
|---|---|---|
| `RequestObserver` | `HTTPClient.perform` (one call site for every request) | `durationMs`, `requestBytes` (pre-deflate), `responseBytes`, `statusCode`, `failed` |
| `UploadObserver` | `DataUploadWorker` | `uploadAttempt(payloadBytes, durationMs, success, retriable)`, `uploadDropped(payloadBytes)` |
| `PayloadObserver` | `FileWriter` | `payloadFinalized(eventCount, serializationMs)` per file |

- `ExporterObservers { spans, coverage }`, each a `Feature { request, upload, payload }`,
  is threaded `Exporter.init` → `SpansExporter`/`CoverageExporter` → their
  `FileWriter` (payload), upload closure (request), and `FeatureStoreAndUpload`
  worker (upload). Logs are not instrumented (no `endpoint` value for logs).
- All hooks are optional and default to `nil`, so the pipeline is a no-op unless
  an observer is attached. `start`/`encodeStart` timestamps are only taken when
  an observer is present.

Adapters that turn the neutral callbacks into `Telemetry.metrics.*` live in
`DatadogSDKTesting/Telemetry/TelemetryObservers.swift`:
- `RequestMetricsObserver` / `UploadMetricsObserver` / `PayloadMetricsObserver` —
  generic bridges taking per-family closures. The common
  `statusCode → error_type` mapping (`Telemetry.errorType(statusCode:)`) lives
  here so every call site agrees.
- Per-family request observers: `gitSettingsRequestObserver`,
  `gitSearchCommitsRequestObserver`, `gitObjectsPackRequestObserver`,
  `skippableTestsRequestObserver`, `knownTestsRequestObserver`,
  `testManagementRequestObserver`.

### Important bug fixed in 3776
The `*ApiService` types now depend on the `HTTPClientType` **protocol** (not the
concrete `HTTPClient`), so a mock client can be injected. The observer-aware
methods are the protocol requirements; no-observer convenience methods are
`@inlinable` protocol-extension defaults.

---

## 5. What is gathered today vs. TODO (SDTEST-3777)

### Gathered (3776)
- **`endpoint_payload.*`** — `requests`, `requests_ms`, `bytes` (request size),
  `requests_errors`, `events_count`, `events_serialization_ms`, tagged
  `test_cycle` (spans) / `code_coverage` (coverage). Wired in
  `DDTracer.endpointPayloadObservers(...)`. This family has **no feature call
  site** — the observers are its only home.
- **API request families** — `git_requests.{settings,search_commits,objects_pack}`
  (+ `_ms`, `_errors`, and `objects_pack_bytes`), `itr_skippable_tests.{request,
  request_ms,request_errors,response_bytes}`, `known_tests.{request,request_ms,
  request_errors,response_bytes}`, `test_management_tests.{…}`. Gathered via the
  per-family request observers passed into the API calls from `GitUploader`, the
  TIA / known-tests / test-management factories, and the settings fetch in
  `DDTestMonitor.getTracerConfig`.

### TODO — SDTEST-3777
1. **Response item counts** (need the parsed result, not the observer — record at
   the call site after the await):
   - `git_requests.objects_pack_files`
   - `git_requests.settings_response` (the 8 boolean flags from the settings response)
   - `itr_skippable_tests.response_tests` / `response_suites`
   - `known_tests.response_tests`
   - `test_management_tests.response_tests`
2. **`endpoint_payload.dropped`** — the `UploadObserver.uploadDropped` hook exists
   but the worker has no retry-exhaustion drop today; failed batches stay on disk
   and are age-purged by `FilesOrchestrator`. Wire `dropped` from the purge path
   (or add an explicit drop) — see `DDTracer.endpointPayloadObservers` where
   `onDropped` is already mapped to `endpointPayload.dropped`.
3. **Local feature metrics** — emitted directly via `SessionConfig.telemetry` /
   the feature's injected `Telemetry`, at the feature instrumentation sites:
   - `events.created` / `events.finished` (+ all their tags: `event_type`,
     `test_framework`, `is_new`, `is_modified`, `is_retry`, `retry_reason`,
     `early_flake_detection_abort_reason`, `is_rum`, `browser_driver`, …) —
     `DDSession`/`Module`/`Suite`/`Test` lifecycle.
   - `session` (`test_session`) and `events.manualApiEvents` — `DDSession`.
   - `events.enqueuedForSerialization`.
   - `git.command` / `git.command_errors` / `git.command_ms` — local `git` CLI in
     `GitUploader` / git info.
   - `git.commit_sha_match` / `git.commit_sha_discrepancy` — git info providers.
   - `itr.skipped` / `itr.unskippable` / `itr.forced_run` — `TestImpactAnalysis`.
   - `code_coverage.{started,finished,is_empty,errors,files}` — coverage feature.
4. **`impacted_tests_detection.*`** — no feature/API exists yet; instruments are
   defined but unused.
5. **`error_type` granularity** — `Telemetry.errorType(statusCode:)` maps `nil`
   status to `.network`; it cannot distinguish `timeout` from `network` without
   the underlying `URLError`. Refine if needed.

---

## 6. File map

EventsExporter:
- `Telemetry/MetricObservers.swift` — observer protocols + `ExporterObservers`.
- `Telemetry/TelemetryExporter.swift` / `TelemetryMetricExporter.swift` — DD
  telemetry intake pipeline (built in SDTEST-3772/3773).
- `API/HTTPClient.swift` — `RequestObserver` measurement; `HTTPClientType` protocol.
- `API/*.swift` — `observer:` param on every method + `@inlinable` conveniences.
- `Upload/DataUploadWorker.swift`, `Utils/Feature.swift` — `UploadObserver`.
- `Persistence/FileWriter.swift` — `PayloadObserver`.
- `{Spans,Coverage}Exporter.swift`, `Exporter.swift` — observer plumbing.

DatadogSDKTesting:
- `Telemetry/Telemetry.swift` — manager + meter provider.
- `Telemetry/TelemetryMetrics.swift` — typed metric tree.
- `Telemetry/TelemetryTags.swift` — tag enums.
- `Telemetry/TelemetryObservers.swift` — observer adapters + per-family observers.
- `DDTracer.swift` — `Telemetry` creation, `exporterObservers(...)`.
- `Config.swift` / `Environment/EnvironmentKeys.swift` — the two env flags.
- `SessionManager.swift` / `Models.swift` (`SessionConfig`) — sharing.
- `DDTestMonitor.swift`, `KnownTests.swift`, `TestManagement.swift`,
  `TestImpactAnalysis/*.swift` — `Telemetry` injected into feature factories.
