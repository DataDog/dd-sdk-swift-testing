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

    // MARK: Reusable metric shapes
    //
    // Most metrics differ only in name, not in shape: an untagged counter, an
    // untagged distribution, or a counter tagged solely by `error_type` /
    // `event_type`. These four cover those cases so the tree doesn't redeclare a
    // near-identical struct per metric. Metrics with a unique tag signature
    // (e.g. `endpoint`, `command`) keep their own struct.

    /// A counter with no tags.
    struct NoTagCounter {
        fileprivate let counter: Counter
        func add(_ count: Int = 1) { counter.add(count, [:]) }
    }

    /// A distribution with no tags.
    struct NoTagDistribution {
        fileprivate let distribution: Distribution
        func record(_ value: Double) { distribution.record(value, [:]) }
    }

    /// A counter tagged only by `error_type`.
    struct ErrorTypeCounter {
        fileprivate let counter: Counter
        func add(_ count: Int = 1, errorType: ErrorType) {
            counter.add(count, ["error_type": errorType])
        }
    }

    /// A counter tagged only by `event_type`.
    struct EventTypeCounter {
        fileprivate let counter: Counter
        func add(_ count: Int = 1, eventType: EventType) {
            counter.add(count, ["event_type": eventType])
        }
    }

    /// A counter tagged only by `endpoint`.
    struct EndpointCounter {
        fileprivate let counter: Counter
        func add(_ count: Int = 1, endpoint: Endpoint) {
            counter.add(count, ["endpoint": endpoint])
        }
    }

    /// A distribution tagged only by `endpoint`.
    struct EndpointDistribution {
        fileprivate let distribution: Distribution
        func record(_ value: Double, endpoint: Endpoint) {
            distribution.record(value, ["endpoint": endpoint])
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
        func noTagCounter(_ name: String) -> NoTagCounter {
            NoTagCounter(counter: counter(name))
        }
        func noTagDistribution(_ name: String) -> NoTagDistribution {
            NoTagDistribution(distribution: distribution(name))
        }
        func errorCounter(_ name: String) -> ErrorTypeCounter {
            ErrorTypeCounter(counter: counter(name))
        }
        func eventCounter(_ name: String) -> EventTypeCounter {
            EventTypeCounter(counter: counter(name))
        }
        func endpointCounter(_ name: String) -> EndpointCounter {
            EndpointCounter(counter: counter(name))
        }
        func endpointDistribution(_ name: String) -> EndpointDistribution {
            EndpointDistribution(distribution: distribution(name))
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
        let manualApiEvents: Telemetry.EventTypeCounter
        let enqueuedForSerialization: Telemetry.NoTagCounter

        init(_ f: Telemetry.Factory) {
            created = Created(counter: f.counter("event_created"))
            finished = Finished(counter: f.counter("event_finished"))
            manualApiEvents = f.eventCounter("manual_api_events")
            enqueuedForSerialization = f.noTagCounter("events_enqueued_for_serialization")
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
        let started: LibraryCounter
        let finished: LibraryCounter
        let isEmpty: Telemetry.NoTagCounter
        let errors: Telemetry.NoTagCounter
        let files: Telemetry.NoTagDistribution

        init(_ f: Telemetry.Factory) {
            started = LibraryCounter(counter: f.counter("code_coverage_started"))
            finished = LibraryCounter(counter: f.counter("code_coverage_finished"))
            isEmpty = f.noTagCounter("code_coverage.is_empty")
            errors = f.noTagCounter("code_coverage.errors")
            files = f.noTagDistribution("code_coverage.files")
        }

        /// Counter tagged by the optional `library` / `test_framework` pair
        /// (`code_coverage_started` / `_finished`).
        struct LibraryCounter {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, library: String? = nil, testFramework: String? = nil) {
                var tags = Telemetry.Tags()
                tags["library"] = library
                tags["test_framework"] = testFramework
                counter.add(count, tags)
            }
        }
    }
}

// MARK: - endpoint payload

extension Telemetry.Metrics {
    struct EndpointPayload {
        let requests: Telemetry.EndpointCounter
        let requestsErrors: RequestsErrors
        let requestsMs: Telemetry.EndpointDistribution
        let eventsCount: Telemetry.EndpointDistribution
        let eventsSerializationMs: Telemetry.EndpointDistribution
        let bytes: Telemetry.EndpointDistribution
        let dropped: Telemetry.EndpointCounter

        init(_ f: Telemetry.Factory) {
            requests = f.endpointCounter("endpoint_payload.requests")
            requestsErrors = RequestsErrors(counter: f.counter("endpoint_payload.requests_errors"))
            requestsMs = f.endpointDistribution("endpoint_payload.requests_ms")
            eventsCount = f.endpointDistribution("endpoint_payload.events_count")
            eventsSerializationMs = f.endpointDistribution("endpoint_payload.events_serialization_ms")
            bytes = f.endpointDistribution("endpoint_payload.bytes")
            dropped = f.endpointCounter("endpoint_payload.dropped")
        }

        /// Counter tagged by both `error_type` and `endpoint`.
        struct RequestsErrors {
            fileprivate let counter: Telemetry.Counter
            func add(_ count: Int = 1, errorType: Telemetry.ErrorType, endpoint: Telemetry.Endpoint) {
                counter.add(count, ["error_type": errorType, "endpoint": endpoint])
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
        let searchCommits: Telemetry.NoTagCounter
        let searchCommitsErrors: Telemetry.ErrorTypeCounter
        let searchCommitsMs: Telemetry.NoTagDistribution
        let objectsPack: Telemetry.NoTagCounter
        let objectsPackErrors: Telemetry.ErrorTypeCounter
        let objectsPackMs: Telemetry.NoTagDistribution
        let objectsPackBytes: Telemetry.NoTagDistribution
        let objectsPackFiles: Telemetry.NoTagDistribution
        let settings: Telemetry.NoTagCounter
        let settingsErrors: Telemetry.ErrorTypeCounter
        let settingsMs: Telemetry.NoTagDistribution
        let settingsResponse: SettingsResponse

        init(_ f: Telemetry.Factory) {
            searchCommits = f.noTagCounter("git_requests.search_commits")
            searchCommitsErrors = f.errorCounter("git_requests.search_commits_errors")
            searchCommitsMs = f.noTagDistribution("git_requests.search_commits_ms")
            objectsPack = f.noTagCounter("git_requests.objects_pack")
            objectsPackErrors = f.errorCounter("git_requests.objects_pack_errors")
            objectsPackMs = f.noTagDistribution("git_requests.objects_pack_ms")
            objectsPackBytes = f.noTagDistribution("git_requests.objects_pack_bytes")
            objectsPackFiles = f.noTagDistribution("git_requests.objects_pack_files")
            settings = f.noTagCounter("git_requests.settings")
            settingsErrors = f.errorCounter("git_requests.settings_errors")
            settingsMs = f.noTagDistribution("git_requests.settings_ms")
            settingsResponse = SettingsResponse(counter: f.counter("git_requests.settings_response"))
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
        let skipped: Telemetry.EventTypeCounter
        let unskippable: Telemetry.EventTypeCounter
        let forcedRun: Telemetry.EventTypeCounter

        init(_ f: Telemetry.Factory) {
            skipped = f.eventCounter("itr_skipped")
            unskippable = f.eventCounter("itr_unskippable")
            forcedRun = f.eventCounter("itr_forced_run")
        }
    }

    struct ITRSkippableTests {
        let request: Telemetry.NoTagCounter
        let requestErrors: Telemetry.ErrorTypeCounter
        let requestMs: Telemetry.NoTagDistribution
        let responseBytes: Telemetry.NoTagDistribution
        /// `itr_skippable_tests.response_tests` / `response_suites` are counts.
        let responseTests: Telemetry.NoTagCounter
        let responseSuites: Telemetry.NoTagCounter

        init(_ f: Telemetry.Factory) {
            request = f.noTagCounter("itr_skippable_tests.request")
            requestErrors = f.errorCounter("itr_skippable_tests.request_errors")
            requestMs = f.noTagDistribution("itr_skippable_tests.request_ms")
            responseBytes = f.noTagDistribution("itr_skippable_tests.response_bytes")
            responseTests = f.noTagCounter("itr_skippable_tests.response_tests")
            responseSuites = f.noTagCounter("itr_skippable_tests.response_suites")
        }
    }
}

// MARK: - known_tests / test_management_tests / impacted_tests_detection

extension Telemetry.Metrics {
    struct KnownTests {
        let request: Telemetry.NoTagCounter
        let requestErrors: Telemetry.ErrorTypeCounter
        let requestMs: Telemetry.NoTagDistribution
        let responseBytes: Telemetry.NoTagDistribution
        /// `known_tests.response_tests` is a distribution.
        let responseTests: Telemetry.NoTagDistribution

        init(_ f: Telemetry.Factory) {
            request = f.noTagCounter("known_tests.request")
            requestErrors = f.errorCounter("known_tests.request_errors")
            requestMs = f.noTagDistribution("known_tests.request_ms")
            responseBytes = f.noTagDistribution("known_tests.response_bytes")
            responseTests = f.noTagDistribution("known_tests.response_tests")
        }
    }

    struct TestManagementTests {
        let request: Telemetry.NoTagCounter
        let requestErrors: Telemetry.ErrorTypeCounter
        let requestMs: Telemetry.NoTagDistribution
        let responseBytes: Telemetry.NoTagDistribution
        let responseTests: Telemetry.NoTagDistribution

        init(_ f: Telemetry.Factory) {
            request = f.noTagCounter("test_management_tests.request")
            requestErrors = f.errorCounter("test_management_tests.request_errors")
            requestMs = f.noTagDistribution("test_management_tests.request_ms")
            responseBytes = f.noTagDistribution("test_management_tests.response_bytes")
            responseTests = f.noTagDistribution("test_management_tests.response_tests")
        }
    }

    struct ImpactedTests {
        let request: Telemetry.NoTagCounter
        let requestErrors: Telemetry.ErrorTypeCounter
        let requestMs: Telemetry.NoTagDistribution
        let responseBytes: Telemetry.NoTagDistribution
        let responseFiles: Telemetry.NoTagDistribution
        let isModified: Telemetry.NoTagCounter

        init(_ f: Telemetry.Factory) {
            request = f.noTagCounter("impacted_tests_detection.request")
            requestErrors = f.errorCounter("impacted_tests_detection.request_errors")
            requestMs = f.noTagDistribution("impacted_tests_detection.request_ms")
            responseBytes = f.noTagDistribution("impacted_tests_detection.response_bytes")
            responseFiles = f.noTagDistribution("impacted_tests_detection.response_files")
            isModified = f.noTagCounter("impacted_tests_detection.is_modified")
        }
    }
}
