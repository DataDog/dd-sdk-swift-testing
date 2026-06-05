# Telemetry architecture

SDK self-telemetry (CI Visibility "instrumentation telemetry" metrics). This
document explains how the pieces fit together.

Milestone history:
- **SDTEST-3775** — the metric instances + the common `Telemetry` manager.
- **SDTEST-3776** — wiring: observer hooks in `EventsExporter`, `Telemetry`
  created with the tracer, request/upload/payload metrics gathered.
- **SDTEST-3777** — all remaining (local + response-count) metrics. Complete.

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

### App-lifecycle protocol
`Telemetry.init` drives the three app-lifecycle telemetry events directly:
- **`app-started`** — sent immediately via `Task.detached { api.sendAppStarted(…) }`
  (no batch, no disk write). The `configuration:` array is populated in
  `DDTracer.telemetryConfiguration()` from `DDTestMonitor.config`: one
  `TelemetryConfigItem` per CI Visibility feature flag, with origin `.envVar` /
  `.default` determined by `EnvironmentReader.has(_:)`.
- **`app-heartbeat`** — a `DispatchSourceTimer` (utility QoS) fires every
  `exportInterval` seconds and calls `telemetryExporter.export(item:
  TelemetryAppHeartbeat())`, batching the heartbeat with the next upload.
- **`app-closing`** — `Telemetry.shutdown()` calls
  `telemetryExporter.export(item: TelemetryAppClosing())` before
  `meterProvider.shutdown()`, so the closing event rides in the same last batch
  as the final metric collection.

---

## 4. Observer hooks (the cross-module bridge)

Defined in `EventsExporter/Telemetry/MetricObservers.swift` (neutral, public):

| Protocol | Reported from | Carries |
|---|---|---|
| `RequestObserver` | `HTTPClient.perform` (one call site for every request) | `durationMs`, `requestBytes` (pre-deflate), `responseBytes`, `statusCode`, `transportError`, `failed` |
| `UploadObserver` | `DataUploadWorker` | `uploadAttempt(payloadBytes, durationMs, success, retriable)`, `uploadDropped(payloadBytes)` |
| `PayloadObserver` | `FileWriter` | `eventEnqueued()` per individual event write; `payloadFinalized(eventCount, serializationMs)` per file |

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
  `requests_errors`, `events_count`, `events_serialization_ms`, `dropped`, tagged
  `test_cycle` (spans) / `code_coverage` (coverage). Wired in
  `DDTracer.endpointPayloadObservers(...)`. This family has **no feature call
  site** — the observers are its only home. `dropped` is reported from
  `FilesOrchestrator` (via its `onDrop` callback → `UploadObserver.uploadDropped`)
  when a stored batch is removed without being uploaded: too old
  (`maxFileAgeForRead`) or purged to keep the directory under `maxDirectorySize`.
  Successful upload deletions (`delete(readableFile:)`) are **not** drops.
- **API request families** — `git_requests.{settings,search_commits,objects_pack}`
  (+ `_ms`, `_errors`, and `objects_pack_bytes`), `itr_skippable_tests.{request,
  request_ms,request_errors,response_bytes}`, `known_tests.{request,request_ms,
  request_errors,response_bytes}`, `test_management_tests.{…}`. Gathered via the
  per-family request observers passed into the API calls from `GitUploader`, the
  TIA / known-tests / test-management factories, and the settings fetch in
  `DDTestMonitor.getTracerConfig`.

### Gathered (3777)
1. **Response item counts** — emitted at the call site, before any empty-response
   guard, and gated on `if let telemetry` to skip computation when disabled:
   - `git_requests.objects_pack_files` — `GitUploader.sendGitInfo` (before upload).
   - `git_requests.settings_response` — `DDTestMonitor.getTracerConfig` local fn;
     convenience overload `add(config: TracerSettings)` on the metric struct keeps
     the call site to one line.
   - `itr_skippable_tests.response_tests` / `response_suites` — `TestImpactAnalysisFactory.fetchTests`.
   - `known_tests.response_tests` — `KnownTestsFactory.fetchTests`.
   - `test_management_tests.response_tests` — `TestManagementFactory.fetchTests`.
2. **Local feature metrics**:
   - `events.created` / `events.finished` / `test_session` — `TelemetryEventsFeature`
     (new; added last in `activeFeatures`). `event_created` fires at the **start**
     hook of each event type (matching dd-trace-go): `testSessionWillStart` /
     `testModuleWillStart` / `testSuiteWillStart` / `testWillStart`. `event_finished`
     fires at the corresponding end hooks; the test `event_finished` fires at
     `testWillFinish` (when all other features' tags are already set). Suite events
     are emitted unconditionally (no empty-suite guard). CI provider comes from
     `session.configuration.env.ci?.provider` — no `DDTestMonitor` access needed.
   - `events.manualApiEvents` — emitted directly in `DDSession.start` / `moduleStart`
     / `DDModule.suiteStart` / `DDSuite.testStart` (`@objc` manual-API paths only;
     auto-instrumented paths go through `TelemetryEventsFeature`).
   - `events.enqueuedForSerialization` — `PayloadObserver.eventEnqueued()`, fired
     from `FileWriter.write` per individual event (before encode), forwarded via
     `PayloadMetricsObserver.onEnqueued`, `testCycle` endpoint only.
   - `git.command` / `git.command_errors` / `git.command_ms` — `GitUploader`:
     `recordedGitCommand<T>(_:cmd:body:)` is the single helper that times any
     throwing command, emits the three metrics, and extracts the real exit code from
     `Spawn.RunError.exitCode` (made public; signals map to 128 + signal number).
     `gitTimed` delegates to it for `get_repository`, `check_shallow`, `unshallow`,
     `get_local_commits`, and `get_objects`. The pack-objects block delegates via the
     same helper, throwing `Spawn.RunError.code(1, …)` when git writes `fatal:` to
     stderr so that case is also counted as an error.
   - `itr.skipped` / `itr.unskippable` / `itr.forced_run` — `TestImpactAnalysis`
     hooks; `unskippable` fires on the first run only (`executions.total == 0`),
     `forced_run` fires only on the final run (`!info.retry.status.isRetry`).
   - `code_coverage.started` — `CodeCoverage.testWillStart` (only when LLVM
     gathering actually starts, checked via the `Bool` return from `_state.update`).
   - `code_coverage.{finished,is_empty,errors,files}` — `BackgroundCoverageProcessor.onEnd`
     (async, on the processor's work queue, after parse completes).
3. **`settings_response.impacted_tests_detection_enabled`** — decoded from the
   `impacted_tests_enabled` JSON field in `SettingsApiService.SettingsResponse` and
   surfaced as `TracerSettings.impactedTestsDetectionEnabled`.
4. **`error_type` granularity** — `RequestObserver.requestFinished` now carries
   `transportError: (any Error)?` (the raw `URLError` from URLSession, nil when an
   HTTP response was received). `HTTPClient` passes it only when `statusCode` is nil.
   `Telemetry.errorType(statusCode:transportError:)` maps `URLError.timedOut` to
   `.timeout` and everything else without a status code to `.network`.

### Still TODO
4. **`git.commit_sha_match` / `git.commit_sha_discrepancy`** — git info providers;
   no CLI path exists.
5. **`impacted_tests_detection.*`** — no feature/API exists yet; instruments are
   defined but unused.

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
- `Telemetry/Telemetry.swift` — manager, meter provider, and app-lifecycle protocol
  (`sendAppStarted` on init, heartbeat timer, `app-closing` in `shutdown`). Holds
  `TelemetryApi` and `TelemetryExporter` references directly.
- `Telemetry/TelemetryMetrics.swift` — typed metric tree; `SettingsResponse` has a
  `add(config: TracerSettings)` convenience overload.
- `Telemetry/TelemetryTags.swift` — tag enums.
- `Telemetry/TelemetryObservers.swift` — observer adapters + per-family observers.
- `Telemetry/TelemetryEventsFeature.swift` — `TestHooksFeature` for event lifecycle
  metrics; must be last in `activeFeatures`. Reads CI provider from
  `session.configuration.env` — no `DDTestMonitor` access.
- `DDTracer.swift` — `Telemetry` creation (`makeTelemetry`), `exporterObservers`,
  `telemetryConfiguration()` (builds `[TelemetryConfigItem]` for `app-started`).
- `Config.swift` / `Environment/EnvironmentKeys.swift` — the two env flags.
- `Models.swift` (`SessionConfig`) — now holds `env: Environment` and
  `config: Config` (both `nonisolated(unsafe)`) so features reach CI/git data via
  `session.configuration.env` without touching `DDTestMonitor`. Removed duplicates:
  `platform`, `service`, `metrics`. `TestSession` / `TestModule` / `TestSuite`
  protocols gained `var configuration: SessionConfig { get }`.
- `SessionManager.swift` — constructs `SessionConfig` with `env` and `config`.
- `DDTestMonitor.swift`, `KnownTests.swift`, `TestManagement.swift`,
  `TestImpactAnalysis/*.swift` — `Telemetry` injected into feature factories.
- `Coverage/CodeCoverage.swift`, `Coverage/BackgroundCoverageProcessor.swift`,
  `Coverage/CodeCoverageProvider.swift` — coverage metrics wired through the stack.
- `DDSession.swift`, `DDModule.swift`, `DDSuite.swift` — manual-API `manualApiEvents`
  and session `test_session` emission; CI provider sourced from `config.env`.

EventsExporter (additions in 3777):
- `Utils/Spawn.swift` — `RunError` made `public`; `exitCode` computed property added
  (`128 + signal` for signal termination, raw code otherwise).
- `API/SettingsApi.swift` — `SettingsResponse.impactedTestsEnabled` decoded from
  `impacted_tests_enabled`; `TracerSettings.impactedTestsDetectionEnabled` exposed.
- `Telemetry/MetricObservers.swift` — `RequestObserver` gained `transportError`;
  `PayloadObserver` gained `eventEnqueued()` (per-event, before encode).
