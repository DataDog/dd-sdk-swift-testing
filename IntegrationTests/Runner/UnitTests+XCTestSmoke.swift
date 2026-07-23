/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import Testing
import TestUtils
@testable import DatadogSDKTesting

@Suite("Integration Tests - XCTest Smoke Unit Tests", .build("UnitTests"), .datadogTesting)
struct UnitTestsXCTestSmoke: IntergationTestSuite {
    @Test func basicPass() async throws {
        try await run(test: "XCBasicPass/testBasicPass") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == true)
            #expect(spans.count == 1)
            let span = try #require(spans.last)
            let meta = span.meta
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(span.resource == "XCBasicPass.testBasicPass")
            #expect(meta[DDTestTags.testName] == "testBasicPass")
            #expect(meta[DDTestTags.testSuite] == "XCBasicPass")
            #expect(meta[DDTestTags.testType] == "test")
        }
    }

    /// The SDK's own instrumentation telemetry round-trips to the backend: the
    /// app-lifecycle events plus self-metrics produced over a basic test run.
    @Test func telemetryReported() async throws {
        try await run(test: "XCBasicPass/testBasicPass") { backend, success in
            #expect(success == true)
            // App-lifecycle: app-started is sent directly; app-closing rides the
            // final batch flushed on shutdown.
            #expect(backend.telemetryEventTypes.contains("app-started"))
            #expect(backend.telemetryEventTypes.contains("app-closing"))
            // Self-metrics reached the backend via generate-metrics — `test_session`
            // is emitted once per session.
            let metricNames = Set(backend.telemetryMetricSeries.map(\.metric))
            #expect(!metricNames.isEmpty)
            #expect(metricNames.contains("test_session"))
        }
    }

    @Test func basicSkip() async throws {
        try await run(test: "XCBasicSkip/testBasicSkip") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == true)
            #expect(spans.count == 1)
            let span = try #require(spans.last)
            let meta = span.meta
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusSkip)
            #expect(span.resource == "XCBasicSkip.testBasicSkip")
            #expect(meta[DDTestTags.testName] == "testBasicSkip")
            #expect(meta[DDTestTags.testSuite] == "XCBasicSkip")
            #expect(meta[DDTestTags.testType] == "test")
        }
    }

    @Test func basicError() async throws {
        try await run(test: "XCBasicError/testBasicError()") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == false)
            #expect(spans.count == 1)
            let span = try #require(spans.last)
            let meta = span.meta
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusFail)
            #expect(span.resource == "XCBasicError.testBasicError")
            #expect(meta[DDTestTags.testName] == "testBasicError")
            #expect(meta[DDTestTags.testSuite] == "XCBasicError")
            #expect(meta[DDTestTags.testType] == "test")
        }
    }

    @Test func asynchronousPass() async throws {
        try await run(test: "XCAsynchronousPass/testAsynchronousPass") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == true)
            #expect(spans.count == 1)
            let span = try #require(spans.last)
            let meta = span.meta
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(span.resource == "XCAsynchronousPass.testAsynchronousPass")
            #expect(meta[DDTestTags.testName] == "testAsynchronousPass")
            #expect(meta[DDTestTags.testSuite] == "XCAsynchronousPass")
            #expect(meta[DDTestTags.testType] == "test")
        }
    }

    @Test func asynchronousSkip() async throws {
        try await run(test: "XCAsynchronousSkip/testAsynchronousSkip") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == true)
            #expect(spans.count == 1)
            let span = try #require(spans.last)
            let meta = span.meta
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusSkip)
            #expect(span.resource == "XCAsynchronousSkip.testAsynchronousSkip")
            #expect(meta[DDTestTags.testName] == "testAsynchronousSkip")
            #expect(meta[DDTestTags.testSuite] == "XCAsynchronousSkip")
            #expect(meta[DDTestTags.testType] == "test")
        }
    }

    @Test func asynchronousError() async throws {
        try await run(test: "XCAsynchronousError/testAsynchronousError") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == false)
            #expect(spans.count == 1)
            let span = try #require(spans.last)
            let meta = span.meta
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusFail)
            #expect(span.resource == "XCAsynchronousError.testAsynchronousError")
            #expect(meta[DDTestTags.testName] == "testAsynchronousError")
            #expect(meta[DDTestTags.testSuite] == "XCAsynchronousError")
            #expect(meta[DDTestTags.testType] == "test")
        }
    }

    @Test func benchmark() async throws {
        try await run(test: "XCBenchmark/testBenchmark") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == true)
            #expect(spans.count == 1)
            let span = try #require(spans.last)
            let meta = span.meta
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(span.resource == "XCBenchmark.testBenchmark")
            #expect(meta[DDTestTags.testName] == "testBenchmark")
            #expect(meta[DDTestTags.testSuite] == "XCBenchmark")
            #expect(meta[DDTestTags.testType] == "benchmark")
        }
    }

    @Test func networkIntegration() async throws {
        try await run(test: "XCNetworkIntegration/testNetworkIntegration") { backend, success in
            let testSpans = backend.allTestSpans
            let infoSpans = backend.allInfoSpans
            #expect(success == true)
            #expect(testSpans.count == 1)
            #expect(infoSpans.count == 1)
            let testSpan = try #require(testSpans.last)
            let meta = testSpan.meta
            let infoMeta = try #require(infoSpans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(testSpan.resource == "XCNetworkIntegration.testNetworkIntegration")
            #expect(meta[DDTestTags.testName] == "testNetworkIntegration")
            #expect(meta[DDTestTags.testSuite] == "XCNetworkIntegration")
            #expect(meta[DDTestTags.testType] == "test")
            #expect(infoMeta["http.method"] == "GET")
        }
    }
    
    /// SDTEST-3913: an Xcode Runtime Issue is a non-failing `XCTIssue`
    /// (`isFailure == false`). It must not trigger DD's own retry/suppression
    /// handling — the test still ends up with a single span, reported as
    /// passed, exactly as XCTest itself sees it, while the issue is still
    /// recorded on the span.
    @Test func runtimeIssueDoesNotFailOrRetry() async throws {
        try await run(test: "XCRuntimeIssue/testNonFailingRuntimeIssue") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == true)
            #expect(spans.count == 1)
            let span = try #require(spans.last)
            let meta = span.meta
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(span.resource == "XCRuntimeIssue.testNonFailingRuntimeIssue")
            #expect(meta[DDTestTags.testName] == "testNonFailingRuntimeIssue")
            #expect(meta[DDTestTags.testSuite] == "XCRuntimeIssue")
            #expect(meta[DDTestTags.testType] == "test")
            // The issue is still recorded on the span, even though it didn't
            // fail the test.
            #expect(meta[DDTags.errorType] != nil)
            #expect(meta[DDTags.errorMessage] != nil)
        }
    }

    @Test(
        .disabled(if: XcodeTestRunner.isWatchOSChildSDK,
                  "KSCrash disables signal/mach exception handlers on watchOS (KSCRASH_HAS_SIGNAL = 0, KSCRASH_HAS_MACH = 0), so SIGILL from Swift array bounds traps cannot be captured.")
    )
    func crash() async throws {
        try await run(test: "XCCrash") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == false)
            #expect(spans.count == 2)
            
            let failedSpan = try #require(spans.first)
            let failed = failedSpan.meta
            #expect(failed[DDTestTags.testStatus] == DDTagValues.statusFail)
            #expect(failedSpan.resource == "XCCrash.testCrash")
            #expect(failed[DDTestTags.testName] == "testCrash")
            #expect(failed[DDTestTags.testSuite] == "XCCrash")
            #expect(failed[DDTestTags.testType] == "test")
            #expect(failed[DDTags.errorType] != nil)
            #expect(failed[DDTags.errorMessage] != nil)
            #expect(failed[DDTags.errorStack] != nil)
            #expect(failed[DDTags.errorCrashLog + ".00"] != nil)
            
            // save all error tags to our test span so we can inspect them in the DD UI
            if let test = DDTest.current {
                let tags = [DDTags.errorType, DDTags.errorMessage, DDTags.errorStack,
                            DDTags.errorCrashLog + ".00", DDTags.errorCrashLog + ".01",
                            DDTags.errorCrashLog + ".02", DDTags.errorCrashLog + ".03",
                            DDTags.errorCrashLog + ".04", DDTags.errorCrashLog + ".05",
                            DDTags.errorCrashLog + ".06", DDTags.errorCrashLog + ".07"]
                for tag in tags {
                    if let value = failed[tag] {
                        test.set(tag: "returned_" + tag, value: value)
                    }
                }
            }
            
            let succeededSpan = try #require(spans.last)
            let succeeded = succeededSpan.meta
            #expect(succeeded[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(succeededSpan.resource == "XCCrash.testNoCrash")
            #expect(succeeded[DDTestTags.testName] == "testNoCrash")
            #expect(succeeded[DDTestTags.testSuite] == "XCCrash")
            #expect(succeeded[DDTestTags.testType] == "test")
            #expect(succeeded[DDTags.errorType] == nil)
            #expect(succeeded[DDTags.errorMessage] == nil)
            #expect(succeeded[DDTags.errorStack] == nil)
            #expect(succeeded[DDTags.errorCrashLog + ".00"] == nil)
        }
    }

    /// Full-stack integration test against the *stripped* framework: spins up
    /// the real SDK in a subprocess that runs
    /// `XCStdoutOTelAndCoverage.testStdoutOTelAndCoverage`, then asserts the
    /// pipelines a stripped consumer still gets reached the backend: one test
    /// span, the stdout-captured `print()` as a log entry, and at least one
    /// coverage payload. The test also drives a second, consumer-owned
    /// OpenTelemetry copy purely to prove it coexists without the
    /// metadata-coalescing crash — those spans are not expected at the backend.
    @Test func stdoutOTelAndCoverage() async throws {
        var config = XcodeTestRunner.Config()
        // Code Coverage is a standalone feature: enable it without TIA/ITR.
        config.backend.settings.codeCoverage = true
        config.environment["DD_CIVISIBILITY_CODE_COVERAGE_ENABLED"] = "true"
        // `enableStdoutInstrumentation` defaults to false; flipping the
        // umbrella DD_CIVISIBILITY_LOGS_ENABLED flag turns on both stdout
        // capture and the OTel LoggerProvider's wiring.
        config.environment["DD_CIVISIBILITY_LOGS_ENABLED"] = "true"

        try await run(test: "XCStdoutOTelAndCoverage/testStdoutOTelAndCoverage", config: config) { backend, success in
            #expect(success == true)

            // 1) Span side — capture the test span's IDs for correlation.
            let spans = backend.allTestSpans
            #expect(spans.count == 1)
            let testSpan = try #require(spans.last)
            #expect(testSpan.meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(testSpan.resource == "XCStdoutOTelAndCoverage.testStdoutOTelAndCoverage")
            #expect(testSpan.meta[DDTestTags.testName] == "testStdoutOTelAndCoverage")
            #expect(testSpan.meta[DDTestTags.testSuite] == "XCStdoutOTelAndCoverage")
            #expect(testSpan.meta[DDTestTags.testType] == "test")
            let testSessionId = try #require(testSpan.testSessionId)
            let testModuleId = try #require(testSpan.testModuleId)
            let testSuiteId = try #require(testSpan.testSuiteId)

            // 2) Logs — the stdout `print()` must be captured and correlate to
            //    the test span via dd.trace_id / dd.span_id.
            let stdoutLog = try #require(backend.allLogs.first { $0.message?.contains("hello from XCTest stdout") == true },
                                         "stdout `print()` should be captured and shipped as a log entry")
            #expect(stdoutLog.fields["dd.trace_id"]?.stringValue == String(testSpan.traceId),
                    "stdout log must correlate to the test span via dd.trace_id")
            #expect(stdoutLog.fields["dd.span_id"]?.stringValue == String(testSpan.spanId),
                    "stdout log must correlate to the test span via dd.span_id")

            // 3) Coverage — the payload must carry the test's session / module /
            //    suite / test span IDs.
            let coverages = backend.allCoverages
            #expect(!coverages.isEmpty, "at least one coverage payload should arrive for the passing test")
            let coverage = try #require(coverages.first { $0.spanId == testSpan.spanId },
                                        "no coverage payload was associated with the test span")
            #expect(coverage.testSessionId == testSessionId)
            #expect(coverage.testSuiteId == testSuiteId)
            // The coverage payload doesn't carry test_module_id directly, so we
            // verify the test span itself does — coverage uploads only happen
            // when DDCoverageHelper.endTest fires inside a module/suite.
            _ = testModuleId
        }
    }
}
