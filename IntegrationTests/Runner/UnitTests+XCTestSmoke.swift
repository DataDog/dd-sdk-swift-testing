/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

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
            let meta = try #require(spans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(meta[DDGenericTags.resource] == "XCBasicPass.testBasicPass")
            #expect(meta[DDTestTags.testName] == "testBasicPass")
            #expect(meta[DDTestTags.testSuite] == "XCBasicPass")
            #expect(meta[DDTestTags.testType] == "test")
        }
    }

    @Test func basicSkip() async throws {
        try await run(test: "XCBasicSkip/testBasicSkip") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == true)
            #expect(spans.count == 1)
            let meta = try #require(spans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusSkip)
            #expect(meta[DDGenericTags.resource] == "XCBasicSkip.testBasicSkip")
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
            let meta = try #require(spans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusFail)
            #expect(meta[DDGenericTags.resource] == "XCBasicError.testBasicError")
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
            let meta = try #require(spans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(meta[DDGenericTags.resource] == "XCAsynchronousPass.testAsynchronousPass")
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
            let meta = try #require(spans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusSkip)
            #expect(meta[DDGenericTags.resource] == "XCAsynchronousSkip.testAsynchronousSkip")
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
            let meta = try #require(spans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusFail)
            #expect(meta[DDGenericTags.resource] == "XCAsynchronousError.testAsynchronousError")
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
            let meta = try #require(spans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(meta[DDGenericTags.resource] == "XCBenchmark.testBenchmark")
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
            let meta = try #require(testSpans.last?.meta)
            let span = try #require(infoSpans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(meta[DDGenericTags.resource] == "XCNetworkIntegration.testNetworkIntegration")
            #expect(meta[DDTestTags.testName] == "testNetworkIntegration")
            #expect(meta[DDTestTags.testSuite] == "XCNetworkIntegration")
            #expect(meta[DDTestTags.testType] == "test")
            #expect(span["http.method"] == "GET")
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
            
            let failed = try #require(spans.first?.meta)
            #expect(failed[DDTestTags.testStatus] == DDTagValues.statusFail)
            #expect(failed[DDGenericTags.resource] == "XCCrash.testCrash")
            #expect(failed[DDTestTags.testName] == "testCrash")
            #expect(failed[DDTestTags.testSuite] == "XCCrash")
            #expect(failed[DDTestTags.testType] == "test")
            #expect(failed[DDTags.errorType] != nil)
            #expect(failed[DDTags.errorMessage] != nil)
            #expect(failed[DDTags.errorStack] != nil)
            #expect(failed[DDTags.errorCrashLog + ".00"] != nil)
            
            // save all error tags to our test span so we can inspect them in the DD UI
            if let test = DatadogSDKTesting.Test.current {
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
            
            let succeeded = try #require(spans.last?.meta)
            #expect(succeeded[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(succeeded[DDGenericTags.resource] == "XCCrash.testNoCrash")
            #expect(succeeded[DDTestTags.testName] == "testNoCrash")
            #expect(succeeded[DDTestTags.testSuite] == "XCCrash")
            #expect(succeeded[DDTestTags.testType] == "test")
            #expect(succeeded[DDTags.errorType] == nil)
            #expect(succeeded[DDTags.errorMessage] == nil)
            #expect(succeeded[DDTags.errorStack] == nil)
            #expect(succeeded[DDTags.errorCrashLog + ".00"] == nil)
        }
    }

    /// Full-stack integration test: spins up the real SDK in a subprocess that
    /// runs `XCStdoutOTelAndCoverage.testStdoutOTelAndCoverage`, then asserts
    /// that all three telemetry pipelines reached the backend with the right
    /// shape: one test span, the stdout-captured `print()` as a log entry, the
    /// OTel `LogRecord` as a log entry (status `warn`), and at least one
    /// coverage payload.
    @Test func stdoutOTelAndCoverage() async throws {
        var config = XcodeTestRunner.Config()
        config.backend.settings.itrEnabled = true
        config.backend.settings.codeCoverage = true
        config.environment["DD_CIVISIBILITY_CODE_COVERAGE_ENABLED"] = "true"

        try await run(test: "XCStdoutOTelAndCoverage/testStdoutOTelAndCoverage", config: config) { backend, success in
            #expect(success == true)

            // 1) Span side — capture the test span's IDs for correlation.
            let spans = backend.allTestSpans
            #expect(spans.count == 1)
            let testSpan = try #require(spans.last)
            #expect(testSpan.meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(testSpan.meta[DDGenericTags.resource] == "XCStdoutOTelAndCoverage.testStdoutOTelAndCoverage")
            #expect(testSpan.meta[DDTestTags.testName] == "testStdoutOTelAndCoverage")
            #expect(testSpan.meta[DDTestTags.testSuite] == "XCStdoutOTelAndCoverage")
            #expect(testSpan.meta[DDTestTags.testType] == "test")
            let testSessionId = try #require(testSpan.testSessionId)
            let testModuleId = try #require(testSpan.testModuleId)
            let testSuiteId = try #require(testSpan.testSuiteId)

            // 2) Logs — both entries must correlate to the test span via
            //    dd.trace_id / dd.span_id and carry the right wire status.
            let stdoutLog = try #require(backend.allLogs.first { $0.message?.contains("hello from XCTest stdout") == true },
                                         "stdout `print()` should be captured and shipped as a log entry")
            let otelLog = try #require(backend.allLogs.first { $0.message?.contains("hello from XCTest OTel") == true },
                                       "an OTel LogRecord should be shipped as a log entry")
            #expect(otelLog.status == "warn", "Severity.warn must map to DDLog.Status.warn on the wire")
            #expect(stdoutLog.fields["dd.trace_id"]?.stringValue == String(testSpan.traceId),
                    "stdout log must correlate to the test span via dd.trace_id")
            #expect(stdoutLog.fields["dd.span_id"]?.stringValue == String(testSpan.spanId),
                    "stdout log must correlate to the test span via dd.span_id")
            #expect(otelLog.fields["dd.trace_id"]?.stringValue == String(testSpan.traceId),
                    "OTel log must correlate to the test span via dd.trace_id")
            #expect(otelLog.fields["dd.span_id"]?.stringValue == String(testSpan.spanId),
                    "OTel log must correlate to the test span via dd.span_id")

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
