/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

// MARK: - Low-level instrument handles

extension Telemetry {
    /// A set of metric tags. Values keep their Swift type (enum / `Bool` / `Int`
    /// / `String`) until the boundary, where `SpanAttributeConvertible` renders
    /// the wire value.
    typealias Tags = [String: any SpanAttributeConvertible]

    /// Thin handle over a telemetry counter. Metric types wrap one of these and
    /// expose a typed `add(...)`; callers don't use this directly. Recording
    /// accumulates a per-interval delta in the shared `MetricStore`.
    struct Counter {
        fileprivate let store: MetricStore
        fileprivate let name: String
        fileprivate func add(_ value: Int, _ tags: Tags) {
            store.addCount(name: name, value: value, tags: Telemetry.renderTags(tags))
        }
    }

    /// Thin handle over a telemetry distribution. Each recorded value is kept as
    /// a raw sample in the shared `MetricStore`; the backend computes the summary.
    struct Distribution {
        fileprivate let store: MetricStore
        fileprivate let name: String
        fileprivate func record(_ value: Double, _ tags: Tags) {
            store.record(name: name, value: value, tags: Telemetry.renderTags(tags))
        }
    }

    /// Names instruments against the shared store; threaded through the metrics
    /// tree so every metric registers itself once at construction.
    struct Factory {
        let store: MetricStore
        func counter(_ name: String) -> Counter {
            Counter(store: store, name: name)
        }
        func distribution(_ name: String) -> Distribution {
            Distribution(store: store, name: name)
        }
    }
}

// MARK: - Metrics tree

extension Telemetry {
    /// The full, discoverable tree of CI Visibility telemetry metrics. Reach a
    /// metric through its group, e.g. `telemetry.metrics.git.command.add(...)`.
    /// Each metric's `add` / `record` names exactly the tags it accepts.
    ///
    /// Metric names mirror the shared instrumentation-telemetry spec (the wire
    /// name is `dd.instrumentation_telemetry_data.civisibility.<name>`) and are
    /// cross-checked against `dd-trace-go`.
    struct Metrics {
        let events: Events
        let session: Session
        let codeCoverage: CodeCoverage
        let endpointPayload: EndpointPayload
        let git: Git
        let gitRequests: GitRequests
        let itr: ITR
        let itrSkippableTests: ITRSkippableTests
        let knownTests: KnownTests
        let testManagementTests: TestManagementTests
        let impactedTests: ImpactedTests

        init(_ f: Factory) {
            events = Events(f)
            session = Session(f)
            codeCoverage = CodeCoverage(f)
            endpointPayload = EndpointPayload(f)
            git = Git(f)
            gitRequests = GitRequests(f)
            itr = ITR(f)
            itrSkippableTests = ITRSkippableTests(f)
            knownTests = KnownTests(f)
            testManagementTests = TestManagementTests(f)
            impactedTests = ImpactedTests(f)
        }
    }
}

// MARK: - events / session

extension Telemetry.Metrics {
    struct Events {
        let created: Created
        let finished: Finished
        let manualApiEvents: ManualApiEvents
        let enqueuedForSerialization: EnqueuedForSerialization

        init(_ f: Telemetry.Factory) {
            created = Created(counter: f.counter("event_created"))
            finished = Finished(counter: f.counter("event_finished"))
            manualApiEvents = ManualApiEvents(counter: f.counter("manual_api_events"))
            enqueuedForSerialization = EnqueuedForSerialization(counter: f.counter("events_enqueued_for_serialization"))
        }

        struct Created {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, testFramework: String, eventType: Telemetry.EventType,
                     hasCodeowner: Bool? = nil, isUnsupportedCI: Bool? = nil, isBenchmark: Bool? = nil) {
                // Assigning a nil optional to a dictionary subscript simply
                // omits the key, so optional tags need no explicit unwrapping.
                var tags: Telemetry.Tags = ["test_framework": testFramework, "event_type": eventType]
                tags["has_codeowner"] = hasCodeowner
                tags["is_unsupported_ci"] = isUnsupportedCI
                tags["is_benchmark"] = isBenchmark
                counter.add(count, tags)
            }
        }

        struct Finished {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, testFramework: String, eventType: Telemetry.EventType,
                     isHeadless: Bool? = nil, hasCodeowner: Bool? = nil, isUnsupportedCI: Bool? = nil,
                     isBenchmark: Bool? = nil, earlyFlakeDetectionAbortReason: Telemetry.EFDAbortReason? = nil,
                     isNew: Bool? = nil, isModified: Bool? = nil, isRetry: Bool? = nil,
                     retryReason: Telemetry.RetryReason? = nil, isRum: Bool? = nil, browserDriver: String? = nil) {
                var tags: Telemetry.Tags = ["test_framework": testFramework, "event_type": eventType]
                tags["is_headless"] = isHeadless
                tags["has_codeowner"] = hasCodeowner
                tags["is_unsupported_ci"] = isUnsupportedCI
                tags["is_benchmark"] = isBenchmark
                tags["early_flake_detection_abort_reason"] = earlyFlakeDetectionAbortReason
                tags["is_new"] = isNew
                tags["is_modified"] = isModified
                tags["is_retry"] = isRetry
                tags["retry_reason"] = retryReason
                tags["is_rum"] = isRum
                tags["browser_driver"] = browserDriver
                counter.add(count, tags)
            }
        }

        struct ManualApiEvents {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, eventType: Telemetry.EventType) {
                counter.add(count, ["event_type": eventType])
            }
        }

        struct EnqueuedForSerialization {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1) { counter.add(count, [:]) }
        }
    }

    /// `test_session` — one metric, exposed as its own group for discoverability.
    struct Session {
        let started: Started

        init(_ f: Telemetry.Factory) {
            started = Started(counter: f.counter("test_session"))
        }

        struct Started {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, provider: String? = nil, autoInjected: Bool? = nil,
                     agentlessLogSubmissionEnabled: Bool? = nil, failFastTestOrderEnabled: Bool? = nil) {
                var tags = Telemetry.Tags()
                tags["provider"] = provider
                tags["auto_injected"] = autoInjected
                tags["agentless_log_submission_enabled"] = agentlessLogSubmissionEnabled
                tags["fail_fast_test_order_enabled"] = failFastTestOrderEnabled
                counter.add(count, tags)
            }
        }
    }
}

// MARK: - code coverage

extension Telemetry.Metrics {
    struct CodeCoverage {
        let started: Started
        let finished: Finished
        let isEmpty: IsEmpty
        let errors: Errors
        let files: Files

        init(_ f: Telemetry.Factory) {
            started = Started(counter: f.counter("code_coverage_started"))
            finished = Finished(counter: f.counter("code_coverage_finished"))
            isEmpty = IsEmpty(counter: f.counter("code_coverage.is_empty"))
            errors = Errors(counter: f.counter("code_coverage.errors"))
            files = Files(distribution: f.distribution("code_coverage.files"))
        }

        struct Started {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, library: String? = nil, testFramework: String? = nil) {
                var tags = Telemetry.Tags()
                tags["library"] = library
                tags["test_framework"] = testFramework
                counter.add(count, tags)
            }
        }

        struct Finished {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, library: String? = nil, testFramework: String? = nil) {
                var tags = Telemetry.Tags()
                tags["library"] = library
                tags["test_framework"] = testFramework
                counter.add(count, tags)
            }
        }

        struct IsEmpty {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1) { counter.add(count, [:]) }
        }

        struct Errors {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1) { counter.add(count, [:]) }
        }

        struct Files {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ files: Double) { distribution.record(files, [:]) }
        }
    }
}

// MARK: - endpoint payload

extension Telemetry.Metrics {
    struct EndpointPayload {
        let requests: Requests
        let requestsErrors: RequestsErrors
        let requestsMs: RequestsMs
        let eventsCount: EventsCount
        let eventsSerializationMs: EventsSerializationMs
        let bytes: Bytes
        let dropped: Dropped

        init(_ f: Telemetry.Factory) {
            requests = Requests(counter: f.counter("endpoint_payload.requests"))
            requestsErrors = RequestsErrors(counter: f.counter("endpoint_payload.requests_errors"))
            requestsMs = RequestsMs(distribution: f.distribution("endpoint_payload.requests_ms"))
            eventsCount = EventsCount(distribution: f.distribution("endpoint_payload.events_count"))
            eventsSerializationMs = EventsSerializationMs(distribution: f.distribution("endpoint_payload.events_serialization_ms"))
            bytes = Bytes(distribution: f.distribution("endpoint_payload.bytes"))
            dropped = Dropped(counter: f.counter("endpoint_payload.dropped"))
        }

        struct Requests {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, endpoint: Telemetry.Endpoint) {
                counter.add(count, ["endpoint": endpoint])
            }
        }

        struct RequestsErrors {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, errorType: Telemetry.ErrorType, endpoint: Telemetry.Endpoint) {
                counter.add(count, ["error_type": errorType, "endpoint": endpoint])
            }
        }

        struct RequestsMs {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ milliseconds: Double, endpoint: Telemetry.Endpoint) {
                distribution.record(milliseconds, ["endpoint": endpoint])
            }
        }

        struct EventsCount {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ events: Double, endpoint: Telemetry.Endpoint) {
                distribution.record(events, ["endpoint": endpoint])
            }
        }

        struct EventsSerializationMs {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ milliseconds: Double, endpoint: Telemetry.Endpoint) {
                distribution.record(milliseconds, ["endpoint": endpoint])
            }
        }

        struct Bytes {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ bytes: Double, endpoint: Telemetry.Endpoint) {
                distribution.record(bytes, ["endpoint": endpoint])
            }
        }

        struct Dropped {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, endpoint: Telemetry.Endpoint) {
                counter.add(count, ["endpoint": endpoint])
            }
        }
    }
}

// MARK: - git

extension Telemetry.Metrics {
    struct Git {
        let command: Command
        let commandErrors: CommandErrors
        let commandMs: CommandMs
        let commitShaMatch: CommitShaMatch
        let commitShaDiscrepancy: CommitShaDiscrepancy

        init(_ f: Telemetry.Factory) {
            command = Command(counter: f.counter("git.command"))
            commandErrors = CommandErrors(counter: f.counter("git.command_errors"))
            commandMs = CommandMs(distribution: f.distribution("git.command_ms"))
            commitShaMatch = CommitShaMatch(counter: f.counter("git.commit_sha_match"))
            commitShaDiscrepancy = CommitShaDiscrepancy(counter: f.counter("git.commit_sha_discrepancy"))
        }

        struct Command {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, command: Telemetry.GitCommand) {
                counter.add(count, ["command": command])
            }
        }

        struct CommandErrors {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, command: Telemetry.GitCommand, exitCode: Int) {
                counter.add(count, ["command": command, "exit_code": exitCode])
            }
        }

        struct CommandMs {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ milliseconds: Double, command: Telemetry.GitCommand) {
                distribution.record(milliseconds, ["command": command])
            }
        }

        struct CommitShaMatch {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, matched: Bool) {
                counter.add(count, ["matched": matched])
            }
        }

        struct CommitShaDiscrepancy {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, expectedProvider: Telemetry.ShaProvider,
                     discrepantProvider: Telemetry.ShaProvider, type: Telemetry.ShaDiscrepancyType) {
                counter.add(count, ["expected_provider": expectedProvider,
                                    "discrepant_provider": discrepantProvider,
                                    "type": type])
            }
        }
    }
}

// MARK: - git_requests

extension Telemetry.Metrics {
    struct GitRequests {
        let searchCommits: SearchCommits
        let searchCommitsErrors: Errors
        let searchCommitsMs: Ms
        let objectsPack: ObjectsPack
        let objectsPackErrors: Errors
        let objectsPackMs: Ms
        let objectsPackBytes: Bytes
        let objectsPackFiles: Files
        let settings: Settings
        let settingsErrors: Errors
        let settingsMs: Ms
        let settingsResponse: SettingsResponse

        init(_ f: Telemetry.Factory) {
            searchCommits = SearchCommits(counter: f.counter("git_requests.search_commits"))
            searchCommitsErrors = Errors(counter: f.counter("git_requests.search_commits_errors"))
            searchCommitsMs = Ms(distribution: f.distribution("git_requests.search_commits_ms"))
            objectsPack = ObjectsPack(counter: f.counter("git_requests.objects_pack"))
            objectsPackErrors = Errors(counter: f.counter("git_requests.objects_pack_errors"))
            objectsPackMs = Ms(distribution: f.distribution("git_requests.objects_pack_ms"))
            objectsPackBytes = Bytes(distribution: f.distribution("git_requests.objects_pack_bytes"))
            objectsPackFiles = Files(distribution: f.distribution("git_requests.objects_pack_files"))
            settings = Settings(counter: f.counter("git_requests.settings"))
            settingsErrors = Errors(counter: f.counter("git_requests.settings_errors"))
            settingsMs = Ms(distribution: f.distribution("git_requests.settings_ms"))
            settingsResponse = SettingsResponse(counter: f.counter("git_requests.settings_response"))
        }

        struct SearchCommits {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1) { counter.add(count, [:]) }
        }

        struct ObjectsPack {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1) { counter.add(count, [:]) }
        }

        struct Settings {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1) { counter.add(count, [:]) }
        }

        /// Shared shape for the three `*_errors` request counters.
        struct Errors {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, errorType: Telemetry.ErrorType) {
                counter.add(count, ["error_type": errorType])
            }
        }

        /// Shared shape for the request-duration distributions.
        struct Ms {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ milliseconds: Double) { distribution.record(milliseconds, [:]) }
        }

        struct Bytes {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ bytes: Double) { distribution.record(bytes, [:]) }
        }

        struct Files {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ files: Double) { distribution.record(files, [:]) }
        }

        struct SettingsResponse {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, coverageEnabled: Bool, itrskipEnabled: Bool, requireGit: Bool,
                     itrEnabled: Bool, earlyFlakeDetectionEnabled: Bool, flakyTestRetriesEnabled: Bool,
                     knownTestsEnabled: Bool, impactedTestsDetectionEnabled: Bool) {
                counter.add(count, [
                    "coverage_enabled": coverageEnabled,
                    "itrskip_enabled": itrskipEnabled,
                    "require_git": requireGit,
                    "itr_enabled": itrEnabled,
                    "early_flake_detection_enabled": earlyFlakeDetectionEnabled,
                    "flaky_test_retries_enabled": flakyTestRetriesEnabled,
                    "known_tests_enabled": knownTestsEnabled,
                    "impacted_tests_detection_enabled": impactedTestsDetectionEnabled,
                ])
            }

            func add(_ count: Int = 1, config: TracerSettings) {
                add(count,
                    coverageEnabled: config.itr.codeCoverage,
                    itrskipEnabled: config.itr.testsSkipping,
                    requireGit: config.itr.requireGit,
                    itrEnabled: config.itr.itrEnabled,
                    earlyFlakeDetectionEnabled: config.efd.enabled,
                    flakyTestRetriesEnabled: config.flakyTestRetriesEnabled,
                    knownTestsEnabled: config.knownTestsEnabled,
                    impactedTestsDetectionEnabled: config.impactedTestsDetectionEnabled)
            }
        }
    }
}

// MARK: - ITR (skip events) and skippable-tests requests

extension Telemetry.Metrics {
    /// Standalone ITR skip-decision counters.
    struct ITR {
        let skipped: EventTypeCounter
        let unskippable: EventTypeCounter
        let forcedRun: EventTypeCounter

        init(_ f: Telemetry.Factory) {
            skipped = EventTypeCounter(counter: f.counter("itr_skipped"))
            unskippable = EventTypeCounter(counter: f.counter("itr_unskippable"))
            forcedRun = EventTypeCounter(counter: f.counter("itr_forced_run"))
        }

        struct EventTypeCounter {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, eventType: Telemetry.EventType) {
                counter.add(count, ["event_type": eventType])
            }
        }
    }

    struct ITRSkippableTests {
        let request: Request
        let requestErrors: RequestErrors
        let requestMs: RequestMs
        let responseBytes: ResponseBytes
        let responseTests: ResponseTests
        let responseSuites: ResponseSuites

        init(_ f: Telemetry.Factory) {
            request = Request(counter: f.counter("itr_skippable_tests.request"))
            requestErrors = RequestErrors(counter: f.counter("itr_skippable_tests.request_errors"))
            requestMs = RequestMs(distribution: f.distribution("itr_skippable_tests.request_ms"))
            responseBytes = ResponseBytes(distribution: f.distribution("itr_skippable_tests.response_bytes"))
            responseTests = ResponseTests(counter: f.counter("itr_skippable_tests.response_tests"))
            responseSuites = ResponseSuites(counter: f.counter("itr_skippable_tests.response_suites"))
        }

        struct Request {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1) { counter.add(count, [:]) }
        }

        struct RequestErrors {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, errorType: Telemetry.ErrorType) {
                counter.add(count, ["error_type": errorType])
            }
        }

        struct RequestMs {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ milliseconds: Double) { distribution.record(milliseconds, [:]) }
        }

        struct ResponseBytes {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ bytes: Double) { distribution.record(bytes, [:]) }
        }

        /// `itr_skippable_tests.response_tests` is a count, not a distribution.
        struct ResponseTests {
            fileprivate let counter: Telemetry.Counter
            func add(_ tests: Int) { counter.add(tests, [:]) }
        }

        /// `itr_skippable_tests.response_suites` is a count, not a distribution.
        struct ResponseSuites {
            fileprivate let counter: Telemetry.Counter
            func add(_ suites: Int) { counter.add(suites, [:]) }
        }
    }
}

// MARK: - known_tests / test_management_tests / impacted_tests_detection

extension Telemetry.Metrics {
    struct KnownTests {
        let request: Request
        let requestErrors: RequestErrors
        let requestMs: RequestMs
        let responseBytes: ResponseBytes
        let responseTests: ResponseTests

        init(_ f: Telemetry.Factory) {
            request = Request(counter: f.counter("known_tests.request"))
            requestErrors = RequestErrors(counter: f.counter("known_tests.request_errors"))
            requestMs = RequestMs(distribution: f.distribution("known_tests.request_ms"))
            responseBytes = ResponseBytes(distribution: f.distribution("known_tests.response_bytes"))
            responseTests = ResponseTests(distribution: f.distribution("known_tests.response_tests"))
        }

        struct Request {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1) { counter.add(count, [:]) }
        }

        struct RequestErrors {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, errorType: Telemetry.ErrorType) {
                counter.add(count, ["error_type": errorType])
            }
        }

        struct RequestMs {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ milliseconds: Double) { distribution.record(milliseconds, [:]) }
        }

        struct ResponseBytes {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ bytes: Double) { distribution.record(bytes, [:]) }
        }

        /// `known_tests.response_tests` is a distribution.
        struct ResponseTests {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ tests: Double) { distribution.record(tests, [:]) }
        }
    }

    struct TestManagementTests {
        let request: Request
        let requestErrors: RequestErrors
        let requestMs: RequestMs
        let responseBytes: ResponseBytes
        let responseTests: ResponseTests

        init(_ f: Telemetry.Factory) {
            request = Request(counter: f.counter("test_management_tests.request"))
            requestErrors = RequestErrors(counter: f.counter("test_management_tests.request_errors"))
            requestMs = RequestMs(distribution: f.distribution("test_management_tests.request_ms"))
            responseBytes = ResponseBytes(distribution: f.distribution("test_management_tests.response_bytes"))
            responseTests = ResponseTests(distribution: f.distribution("test_management_tests.response_tests"))
        }

        struct Request {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1) { counter.add(count, [:]) }
        }

        struct RequestErrors {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, errorType: Telemetry.ErrorType) {
                counter.add(count, ["error_type": errorType])
            }
        }

        struct RequestMs {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ milliseconds: Double) { distribution.record(milliseconds, [:]) }
        }

        struct ResponseBytes {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ bytes: Double) { distribution.record(bytes, [:]) }
        }

        struct ResponseTests {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ tests: Double) { distribution.record(tests, [:]) }
        }
    }

    struct ImpactedTests {
        let request: Request
        let requestErrors: RequestErrors
        let requestMs: RequestMs
        let responseBytes: ResponseBytes
        let responseFiles: ResponseFiles
        let isModified: IsModified

        init(_ f: Telemetry.Factory) {
            request = Request(counter: f.counter("impacted_tests_detection.request"))
            requestErrors = RequestErrors(counter: f.counter("impacted_tests_detection.request_errors"))
            requestMs = RequestMs(distribution: f.distribution("impacted_tests_detection.request_ms"))
            responseBytes = ResponseBytes(distribution: f.distribution("impacted_tests_detection.response_bytes"))
            responseFiles = ResponseFiles(distribution: f.distribution("impacted_tests_detection.response_files"))
            isModified = IsModified(counter: f.counter("impacted_tests_detection.is_modified"))
        }

        struct Request {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1) { counter.add(count, [:]) }
        }

        struct RequestErrors {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, errorType: Telemetry.ErrorType) {
                counter.add(count, ["error_type": errorType])
            }
        }

        struct RequestMs {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ milliseconds: Double) { distribution.record(milliseconds, [:]) }
        }

        struct ResponseBytes {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ bytes: Double) { distribution.record(bytes, [:]) }
        }

        struct ResponseFiles {
            fileprivate let distribution: Telemetry.Distribution
            func record(_ files: Double) { distribution.record(files, [:]) }
        }

        struct IsModified {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1) { counter.add(count, [:]) }
        }
    }
}
