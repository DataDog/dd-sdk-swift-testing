/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

// MARK: - TelemetryMetricTags protocol

protocol TelemetryMetricTags {
    var tags: [String: any SpanAttributeConvertible] { get }
}

extension TelemetryMetricTags {
    func renderTags() -> Set<String> {
        Set(tags.map { "\($0.key):\($0.value.spanAttribute)" })
    }
}

// MARK: - Core metric instruments

extension Telemetry {
    /// Thin handle over a telemetry counter. Extensions constrained to a specific
    /// `Tags` type expose a typed `add(...)`; callers use those, not this directly.
    struct Counter<Tags: TelemetryMetricTags> {
        fileprivate let store: MetricStore
        fileprivate let name: String
        fileprivate func add(_ value: Int, _ tags: Tags) {
            store.addCount(name: name, value: value, tags: tags.renderTags())
        }
    }

    /// Thin handle over a telemetry distribution. Each recorded value is kept as
    /// a raw sample; the backend computes the statistical summary.
    struct Distribution<Tags: TelemetryMetricTags> {
        fileprivate let store: MetricStore
        fileprivate let name: String
        fileprivate func record(_ value: Double, _ tags: Tags) {
            store.record(name: name, value: value, tags: tags.renderTags())
        }
    }

    /// Names instruments against the shared store; threaded through the metrics
    /// tree so every metric registers itself once at construction.
    struct Factory {
        let store: MetricStore
        func counter<T: TelemetryMetricTags>(_ name: String) -> Counter<T> {
            Counter(store: store, name: name)
        }
        func distribution<T: TelemetryMetricTags>(_ name: String) -> Distribution<T> {
            Distribution(store: store, name: name)
        }
    }
}

// MARK: - Common MetricTags

extension Telemetry {
    struct EmptyMetricTags: TelemetryMetricTags {
        var tags: [String: any SpanAttributeConvertible] { [:] }
    }

    struct ErrorTypeMetricTags: TelemetryMetricTags {
        var errorType: ErrorType
        var tags: [String: any SpanAttributeConvertible] { ["error_type": errorType] }
    }

    struct EventTypeMetricTags: TelemetryMetricTags {
        var eventType: EventType
        var tags: [String: any SpanAttributeConvertible] { ["event_type": eventType] }
    }

    struct EndpointMetricTags: TelemetryMetricTags {
        var endpoint: Endpoint
        var tags: [String: any SpanAttributeConvertible] { ["endpoint": endpoint] }
    }
}

extension Dictionary: TelemetryMetricTags where Key == String, Value == (any SpanAttributeConvertible) {
    var tags: [String: any SpanAttributeConvertible] { self }
}

extension Telemetry.Counter where Tags == Telemetry.EmptyMetricTags {
    func add(_ count: Int = 1) { add(count, Tags()) }
}

extension Telemetry.Distribution where Tags == Telemetry.EmptyMetricTags {
    func record(_ value: Double) { record(value, Tags()) }
}

extension Telemetry.Counter where Tags == Telemetry.ErrorTypeMetricTags {
    func add(_ count: Int = 1, errorType: Telemetry.ErrorType) {
        add(count, Tags(errorType: errorType))
    }
}

extension Telemetry.Counter where Tags == Telemetry.EventTypeMetricTags {
    func add(_ count: Int = 1, eventType: Telemetry.EventType) {
        add(count, Tags(eventType: eventType))
    }
}

extension Telemetry.Counter where Tags == Telemetry.EndpointMetricTags {
    func add(_ count: Int = 1, endpoint: Telemetry.Endpoint) {
        add(count, Tags(endpoint: endpoint))
    }
}

extension Telemetry.Distribution where Tags == Telemetry.EndpointMetricTags {
    func record(_ value: Double, endpoint: Telemetry.Endpoint) {
        record(value, Tags(endpoint: endpoint))
    }
}

// MARK: - Metrics tree

extension Telemetry {
    /// The full, discoverable tree of CI Visibility telemetry metrics. Reach a
    /// metric through its group, e.g. `telemetry.metrics.git.command.add(...)`.
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

extension Telemetry {
    struct CreatedEventMetricTags: TelemetryMetricTags {
        var testFramework: String
        var eventType: EventType
        var hasCodeowner: Bool?
        var isUnsupportedCI: Bool?
        var isBenchmark: Bool?
        var tags: [String: any SpanAttributeConvertible] {
            var t: [String: any SpanAttributeConvertible] = ["test_framework": testFramework, "event_type": eventType]
            t["has_codeowner"] = hasCodeowner
            t["is_unsupported_ci"] = isUnsupportedCI
            t["is_benchmark"] = isBenchmark
            return t
        }
    }

    struct FinishedEventMetricTags: TelemetryMetricTags {
        var testFramework: String
        var eventType: EventType
        var isHeadless: Bool?
        var hasCodeowner: Bool?
        var isUnsupportedCI: Bool?
        var isBenchmark: Bool?
        var earlyFlakeDetectionAbortReason: EFDAbortReason?
        var isNew: Bool?
        var isModified: Bool?
        var isRetry: Bool?
        var retryReason: RetryReason?
        var isRum: Bool?
        var browserDriver: String?
        var tags: [String: any SpanAttributeConvertible] {
            var t: [String: any SpanAttributeConvertible] = ["test_framework": testFramework, "event_type": eventType]
            t["is_headless"] = isHeadless
            t["has_codeowner"] = hasCodeowner
            t["is_unsupported_ci"] = isUnsupportedCI
            t["is_benchmark"] = isBenchmark
            t["early_flake_detection_abort_reason"] = earlyFlakeDetectionAbortReason
            t["is_new"] = isNew
            t["is_modified"] = isModified
            t["is_retry"] = isRetry
            t["retry_reason"] = retryReason
            t["is_rum"] = isRum
            t["browser_driver"] = browserDriver
            return t
        }
    }

    struct SessionStartedMetricTags: TelemetryMetricTags {
        var provider: String?
        var autoInjected: Bool?
        var agentlessLogSubmissionEnabled: Bool?
        var failFastTestOrderEnabled: Bool?
        var tags: [String: any SpanAttributeConvertible] {
            var t = [String: any SpanAttributeConvertible]()
            t["provider"] = provider
            t["auto_injected"] = autoInjected
            t["agentless_log_submission_enabled"] = agentlessLogSubmissionEnabled
            t["fail_fast_test_order_enabled"] = failFastTestOrderEnabled
            return t
        }
    }
}

extension Telemetry.Counter where Tags == Telemetry.CreatedEventMetricTags {
    func add(_ count: Int = 1, testFramework: String, eventType: Telemetry.EventType,
             hasCodeowner: Bool? = nil, isUnsupportedCI: Bool? = nil, isBenchmark: Bool? = nil) {
        add(count, Tags(testFramework: testFramework, eventType: eventType,
                        hasCodeowner: hasCodeowner, isUnsupportedCI: isUnsupportedCI, isBenchmark: isBenchmark))
    }
}

extension Telemetry.Counter where Tags == Telemetry.FinishedEventMetricTags {
    func add(_ count: Int = 1, testFramework: String, eventType: Telemetry.EventType,
             isHeadless: Bool? = nil, hasCodeowner: Bool? = nil, isUnsupportedCI: Bool? = nil,
             isBenchmark: Bool? = nil, earlyFlakeDetectionAbortReason: Telemetry.EFDAbortReason? = nil,
             isNew: Bool? = nil, isModified: Bool? = nil, isRetry: Bool? = nil,
             retryReason: Telemetry.RetryReason? = nil, isRum: Bool? = nil, browserDriver: String? = nil) {
        add(count, Tags(testFramework: testFramework, eventType: eventType,
                        isHeadless: isHeadless, hasCodeowner: hasCodeowner, isUnsupportedCI: isUnsupportedCI,
                        isBenchmark: isBenchmark, earlyFlakeDetectionAbortReason: earlyFlakeDetectionAbortReason,
                        isNew: isNew, isModified: isModified, isRetry: isRetry,
                        retryReason: retryReason, isRum: isRum, browserDriver: browserDriver))
    }
}

extension Telemetry.Counter where Tags == Telemetry.SessionStartedMetricTags {
    func add(_ count: Int = 1, provider: String? = nil, autoInjected: Bool? = nil,
             agentlessLogSubmissionEnabled: Bool? = nil, failFastTestOrderEnabled: Bool? = nil) {
        add(count, Tags(provider: provider, autoInjected: autoInjected,
                        agentlessLogSubmissionEnabled: agentlessLogSubmissionEnabled,
                        failFastTestOrderEnabled: failFastTestOrderEnabled))
    }
}

extension Telemetry.Metrics {
    struct Events {
        let created: Telemetry.Counter<Telemetry.CreatedEventMetricTags>
        let finished: Telemetry.Counter<Telemetry.FinishedEventMetricTags>
        let manualApiEvents: Telemetry.Counter<Telemetry.EventTypeMetricTags>
        let enqueuedForSerialization: Telemetry.Counter<Telemetry.EmptyMetricTags>

        init(_ f: Telemetry.Factory) {
            created = f.counter("event_created")
            finished = f.counter("event_finished")
            manualApiEvents = f.counter("manual_api_events")
            enqueuedForSerialization = f.counter("events_enqueued_for_serialization")
        }
    }

    struct Session {
        let started: Telemetry.Counter<Telemetry.SessionStartedMetricTags>

        init(_ f: Telemetry.Factory) {
            started = f.counter("test_session")
        }
    }
}

// MARK: - code coverage

extension Telemetry {
    struct LibraryCoverageMetricTags: TelemetryMetricTags {
        var library: String?
        var testFramework: String?
        var tags: [String: any SpanAttributeConvertible] {
            var t = [String: any SpanAttributeConvertible]()
            t["library"] = library
            t["test_framework"] = testFramework
            return t
        }
    }
}

extension Telemetry.Counter where Tags == Telemetry.LibraryCoverageMetricTags {
    func add(_ count: Int = 1, library: String? = nil, testFramework: String? = nil) {
        add(count, Tags(library: library, testFramework: testFramework))
    }
}

extension Telemetry.Metrics {
    struct CodeCoverage {
        let started: Telemetry.Counter<Telemetry.LibraryCoverageMetricTags>
        let finished: Telemetry.Counter<Telemetry.LibraryCoverageMetricTags>
        let isEmpty: Telemetry.Counter<Telemetry.EmptyMetricTags>
        let errors: Telemetry.Counter<Telemetry.EmptyMetricTags>
        let files: Telemetry.Distribution<Telemetry.EmptyMetricTags>

        init(_ f: Telemetry.Factory) {
            started = f.counter("code_coverage_started")
            finished = f.counter("code_coverage_finished")
            isEmpty = f.counter("code_coverage.is_empty")
            errors = f.counter("code_coverage.errors")
            files = f.distribution("code_coverage.files")
        }
    }
}

// MARK: - endpoint payload

extension Telemetry {
    struct RequestsErrorsMetricTags: TelemetryMetricTags {
        var errorType: ErrorType
        var endpoint: Endpoint
        var tags: [String: any SpanAttributeConvertible] {
            ["error_type": errorType, "endpoint": endpoint]
        }
    }
}

extension Telemetry.Counter where Tags == Telemetry.RequestsErrorsMetricTags {
    func add(_ count: Int = 1, errorType: Telemetry.ErrorType, endpoint: Telemetry.Endpoint) {
        add(count, Tags(errorType: errorType, endpoint: endpoint))
    }
}

extension Telemetry.Metrics {
    struct EndpointPayload {
        let requests: Telemetry.Counter<Telemetry.EndpointMetricTags>
        let requestsErrors: Telemetry.Counter<Telemetry.RequestsErrorsMetricTags>
        let requestsMs: Telemetry.Distribution<Telemetry.EndpointMetricTags>
        let eventsCount: Telemetry.Distribution<Telemetry.EndpointMetricTags>
        let eventsSerializationMs: Telemetry.Distribution<Telemetry.EndpointMetricTags>
        let bytes: Telemetry.Distribution<Telemetry.EndpointMetricTags>
        let dropped: Telemetry.Counter<Telemetry.EndpointMetricTags>

        init(_ f: Telemetry.Factory) {
            requests = f.counter("endpoint_payload.requests")
            requestsErrors = f.counter("endpoint_payload.requests_errors")
            requestsMs = f.distribution("endpoint_payload.requests_ms")
            eventsCount = f.distribution("endpoint_payload.events_count")
            eventsSerializationMs = f.distribution("endpoint_payload.events_serialization_ms")
            bytes = f.distribution("endpoint_payload.bytes")
            dropped = f.counter("endpoint_payload.dropped")
        }
    }
}

// MARK: - git

extension Telemetry {
    struct GitCommandMetricTags: TelemetryMetricTags {
        var command: GitCommand
        var tags: [String: any SpanAttributeConvertible] { ["command": command] }
    }

    struct GitCommandErrorsMetricTags: TelemetryMetricTags {
        var command: GitCommand
        var exitCode: Int
        var tags: [String: any SpanAttributeConvertible] { ["command": command, "exit_code": exitCode] }
    }

    struct CommitShaMatchMetricTags: TelemetryMetricTags {
        var matched: Bool
        var tags: [String: any SpanAttributeConvertible] { ["matched": matched] }
    }

    struct CommitShaDiscrepancyMetricTags: TelemetryMetricTags {
        var expectedProvider: ShaProvider
        var discrepantProvider: ShaProvider
        var type: ShaDiscrepancyType
        var tags: [String: any SpanAttributeConvertible] {
            ["expected_provider": expectedProvider, "discrepant_provider": discrepantProvider, "type": type]
        }
    }
}

extension Telemetry.Counter where Tags == Telemetry.GitCommandMetricTags {
    func add(_ count: Int = 1, command: Telemetry.GitCommand) {
        add(count, Tags(command: command))
    }
}

extension Telemetry.Distribution where Tags == Telemetry.GitCommandMetricTags {
    func record(_ milliseconds: Double, command: Telemetry.GitCommand) {
        record(milliseconds, Tags(command: command))
    }
}

extension Telemetry.Counter where Tags == Telemetry.GitCommandErrorsMetricTags {
    func add(_ count: Int = 1, command: Telemetry.GitCommand, exitCode: Int) {
        add(count, Tags(command: command, exitCode: exitCode))
    }
}

extension Telemetry.Counter where Tags == Telemetry.CommitShaMatchMetricTags {
    func add(_ count: Int = 1, matched: Bool) {
        add(count, Tags(matched: matched))
    }
}

extension Telemetry.Counter where Tags == Telemetry.CommitShaDiscrepancyMetricTags {
    func add(_ count: Int = 1, expectedProvider: Telemetry.ShaProvider,
             discrepantProvider: Telemetry.ShaProvider, type: Telemetry.ShaDiscrepancyType) {
        add(count, Tags(expectedProvider: expectedProvider, discrepantProvider: discrepantProvider, type: type))
    }
}

extension Telemetry.Metrics {
    struct Git {
        let command: Telemetry.Counter<Telemetry.GitCommandMetricTags>
        let commandErrors: Telemetry.Counter<Telemetry.GitCommandErrorsMetricTags>
        let commandMs: Telemetry.Distribution<Telemetry.GitCommandMetricTags>
        let commitShaMatch: Telemetry.Counter<Telemetry.CommitShaMatchMetricTags>
        let commitShaDiscrepancy: Telemetry.Counter<Telemetry.CommitShaDiscrepancyMetricTags>

        init(_ f: Telemetry.Factory) {
            command = f.counter("git.command")
            commandErrors = f.counter("git.command_errors")
            commandMs = f.distribution("git.command_ms")
            commitShaMatch = f.counter("git.commit_sha_match")
            commitShaDiscrepancy = f.counter("git.commit_sha_discrepancy")
        }
    }
}

// MARK: - git_requests

extension Telemetry {
    struct SettingsResponseMetricTags: TelemetryMetricTags {
        var coverageEnabled: Bool
        var itrskipEnabled: Bool
        var requireGit: Bool
        var itrEnabled: Bool
        var earlyFlakeDetectionEnabled: Bool
        var flakyTestRetriesEnabled: Bool
        var knownTestsEnabled: Bool
        var impactedTestsDetectionEnabled: Bool
        var tags: [String: any SpanAttributeConvertible] {
            [
                "coverage_enabled": coverageEnabled,
                "itrskip_enabled": itrskipEnabled,
                "require_git": requireGit,
                "itr_enabled": itrEnabled,
                "early_flake_detection_enabled": earlyFlakeDetectionEnabled,
                "flaky_test_retries_enabled": flakyTestRetriesEnabled,
                "known_tests_enabled": knownTestsEnabled,
                "impacted_tests_detection_enabled": impactedTestsDetectionEnabled,
            ]
        }
    }
}

extension Telemetry.Counter where Tags == Telemetry.SettingsResponseMetricTags {
    func add(_ count: Int = 1, coverageEnabled: Bool, itrskipEnabled: Bool, requireGit: Bool,
             itrEnabled: Bool, earlyFlakeDetectionEnabled: Bool, flakyTestRetriesEnabled: Bool,
             knownTestsEnabled: Bool, impactedTestsDetectionEnabled: Bool) {
        add(count, Tags(coverageEnabled: coverageEnabled, itrskipEnabled: itrskipEnabled,
                        requireGit: requireGit, itrEnabled: itrEnabled,
                        earlyFlakeDetectionEnabled: earlyFlakeDetectionEnabled,
                        flakyTestRetriesEnabled: flakyTestRetriesEnabled,
                        knownTestsEnabled: knownTestsEnabled,
                        impactedTestsDetectionEnabled: impactedTestsDetectionEnabled))
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

extension Telemetry.Metrics {
    struct GitRequests {
        let searchCommits: Telemetry.Counter<Telemetry.EmptyMetricTags>
        let searchCommitsErrors: Telemetry.Counter<Telemetry.ErrorTypeMetricTags>
        let searchCommitsMs: Telemetry.Distribution<Telemetry.EmptyMetricTags>
        let objectsPack: Telemetry.Counter<Telemetry.EmptyMetricTags>
        let objectsPackErrors: Telemetry.Counter<Telemetry.ErrorTypeMetricTags>
        let objectsPackMs: Telemetry.Distribution<Telemetry.EmptyMetricTags>
        let objectsPackBytes: Telemetry.Distribution<Telemetry.EmptyMetricTags>
        let objectsPackFiles: Telemetry.Distribution<Telemetry.EmptyMetricTags>
        let settings: Telemetry.Counter<Telemetry.EmptyMetricTags>
        let settingsErrors: Telemetry.Counter<Telemetry.ErrorTypeMetricTags>
        let settingsMs: Telemetry.Distribution<Telemetry.EmptyMetricTags>
        let settingsResponse: Telemetry.Counter<Telemetry.SettingsResponseMetricTags>

        init(_ f: Telemetry.Factory) {
            searchCommits = f.counter("git_requests.search_commits")
            searchCommitsErrors = f.counter("git_requests.search_commits_errors")
            searchCommitsMs = f.distribution("git_requests.search_commits_ms")
            objectsPack = f.counter("git_requests.objects_pack")
            objectsPackErrors = f.counter("git_requests.objects_pack_errors")
            objectsPackMs = f.distribution("git_requests.objects_pack_ms")
            objectsPackBytes = f.distribution("git_requests.objects_pack_bytes")
            objectsPackFiles = f.distribution("git_requests.objects_pack_files")
            settings = f.counter("git_requests.settings")
            settingsErrors = f.counter("git_requests.settings_errors")
            settingsMs = f.distribution("git_requests.settings_ms")
            settingsResponse = f.counter("git_requests.settings_response")
        }
    }
}

// MARK: - ITR (skip events) and skippable-tests requests

extension Telemetry.Metrics {
    struct ITR {
        let skipped: Telemetry.Counter<Telemetry.EventTypeMetricTags>
        let unskippable: Telemetry.Counter<Telemetry.EventTypeMetricTags>
        let forcedRun: Telemetry.Counter<Telemetry.EventTypeMetricTags>

        init(_ f: Telemetry.Factory) {
            skipped = f.counter("itr_skipped")
            unskippable = f.counter("itr_unskippable")
            forcedRun = f.counter("itr_forced_run")
        }
    }

    struct ITRSkippableTests {
        let request: Telemetry.Counter<Telemetry.EmptyMetricTags>
        let requestErrors: Telemetry.Counter<Telemetry.ErrorTypeMetricTags>
        let requestMs: Telemetry.Distribution<Telemetry.EmptyMetricTags>
        let responseBytes: Telemetry.Distribution<Telemetry.EmptyMetricTags>
        let responseTests: Telemetry.Counter<Telemetry.EmptyMetricTags>
        let responseSuites: Telemetry.Counter<Telemetry.EmptyMetricTags>

        init(_ f: Telemetry.Factory) {
            request = f.counter("itr_skippable_tests.request")
            requestErrors = f.counter("itr_skippable_tests.request_errors")
            requestMs = f.distribution("itr_skippable_tests.request_ms")
            responseBytes = f.distribution("itr_skippable_tests.response_bytes")
            responseTests = f.counter("itr_skippable_tests.response_tests")
            responseSuites = f.counter("itr_skippable_tests.response_suites")
        }
    }
}

// MARK: - known_tests / test_management_tests / impacted_tests_detection

extension Telemetry.Metrics {
    struct KnownTests {
        let request: Telemetry.Counter<Telemetry.EmptyMetricTags>
        let requestErrors: Telemetry.Counter<Telemetry.ErrorTypeMetricTags>
        let requestMs: Telemetry.Distribution<Telemetry.EmptyMetricTags>
        let responseBytes: Telemetry.Distribution<Telemetry.EmptyMetricTags>
        let responseTests: Telemetry.Distribution<Telemetry.EmptyMetricTags>

        init(_ f: Telemetry.Factory) {
            request = f.counter("known_tests.request")
            requestErrors = f.counter("known_tests.request_errors")
            requestMs = f.distribution("known_tests.request_ms")
            responseBytes = f.distribution("known_tests.response_bytes")
            responseTests = f.distribution("known_tests.response_tests")
        }
    }

    struct TestManagementTests {
        let request: Telemetry.Counter<Telemetry.EmptyMetricTags>
        let requestErrors: Telemetry.Counter<Telemetry.ErrorTypeMetricTags>
        let requestMs: Telemetry.Distribution<Telemetry.EmptyMetricTags>
        let responseBytes: Telemetry.Distribution<Telemetry.EmptyMetricTags>
        let responseTests: Telemetry.Distribution<Telemetry.EmptyMetricTags>

        init(_ f: Telemetry.Factory) {
            request = f.counter("test_management_tests.request")
            requestErrors = f.counter("test_management_tests.request_errors")
            requestMs = f.distribution("test_management_tests.request_ms")
            responseBytes = f.distribution("test_management_tests.response_bytes")
            responseTests = f.distribution("test_management_tests.response_tests")
        }
    }

    struct ImpactedTests {
        let request: Telemetry.Counter<Telemetry.EmptyMetricTags>
        let requestErrors: Telemetry.Counter<Telemetry.ErrorTypeMetricTags>
        let requestMs: Telemetry.Distribution<Telemetry.EmptyMetricTags>
        let responseBytes: Telemetry.Distribution<Telemetry.EmptyMetricTags>
        let responseFiles: Telemetry.Distribution<Telemetry.EmptyMetricTags>
        let isModified: Telemetry.Counter<Telemetry.EmptyMetricTags>

        init(_ f: Telemetry.Factory) {
            request = f.counter("impacted_tests_detection.request")
            requestErrors = f.counter("impacted_tests_detection.request_errors")
            requestMs = f.distribution("impacted_tests_detection.request_ms")
            responseBytes = f.distribution("impacted_tests_detection.response_bytes")
            responseFiles = f.distribution("impacted_tests_detection.response_files")
            isModified = f.counter("impacted_tests_detection.is_modified")
        }
    }
}
