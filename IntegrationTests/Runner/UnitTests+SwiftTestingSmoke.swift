/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import Testing
import TestUtils
@testable import DatadogSDKTesting

@Suite("Integration Tests - Swift Testing Smoke Unit Tests", .build("UnitTests"), .datadogTesting)
struct UnitTestsSwiftTestingSmoke: IntergationTestSuite {
    @Test func basicPass() async throws {
        try await run(test: "STBasicPass/basicPass()") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == true)
            #expect(spans.count == 1)
            let span = try #require(spans.last)
            let meta = span.meta
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(span.resource == "STBasicPass.basicPass")
            #expect(meta[DDTestTags.testName] == "basicPass")
            #expect(meta[DDTestTags.testSuite] == "STBasicPass")
            #expect(meta[DDTestTags.testType] == "test")
        }
    }

    @Test func basicSkip() async throws {
        try await run(test: "STBasicSkip/basicSkip()") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == true)
            #expect(spans.count == 1)
            let span = try #require(spans.last)
            let meta = span.meta
            #if compiler(>=6.3)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusSkip)
            #else
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #endif
            #expect(span.resource == "STBasicSkip.basicSkip")
            #expect(meta[DDTestTags.testName] == "basicSkip")
            #expect(meta[DDTestTags.testSuite] == "STBasicSkip")
            #expect(meta[DDTestTags.testType] == "test")
        }
    }

    @Test func basicError() async throws {
        try await run(test: "STBasicError/basicError()") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == false)
            #expect(spans.count == 1)
            let span = try #require(spans.last)
            let meta = span.meta
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusFail)
            #expect(span.resource == "STBasicError.basicError")
            #expect(meta[DDTestTags.testName] == "basicError")
            #expect(meta[DDTestTags.testSuite] == "STBasicError")
            #expect(meta[DDTestTags.testType] == "test")
        }
    }

    @Test func asynchronousPass() async throws {
        try await run(test: "STAsynchronousPass/asynchronousPass()") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == true)
            #expect(spans.count == 1)
            let span = try #require(spans.last)
            let meta = span.meta
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(span.resource == "STAsynchronousPass.asynchronousPass")
            #expect(meta[DDTestTags.testName] == "asynchronousPass")
            #expect(meta[DDTestTags.testSuite] == "STAsynchronousPass")
            #expect(meta[DDTestTags.testType] == "test")
        }
    }

    @Test func asynchronousSkip() async throws {
        try await run(test: "STAsynchronousSkip/asynchronousSkip()") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == true)
            #expect(spans.count == 1)
            let span = try #require(spans.last)
            let meta = span.meta
            #if compiler(>=6.3)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusSkip)
            #else
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #endif
            #expect(span.resource == "STAsynchronousSkip.asynchronousSkip")
            #expect(meta[DDTestTags.testName] == "asynchronousSkip")
            #expect(meta[DDTestTags.testSuite] == "STAsynchronousSkip")
            #expect(meta[DDTestTags.testType] == "test")
        }
    }

    @Test func asynchronousError() async throws {
        try await run(test: "STAsynchronousError/asynchronousError()") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == false)
            #expect(spans.count == 1)
            let span = try #require(spans.last)
            let meta = span.meta
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusFail)
            #expect(span.resource == "STAsynchronousError.asynchronousError")
            #expect(meta[DDTestTags.testName] == "asynchronousError")
            #expect(meta[DDTestTags.testSuite] == "STAsynchronousError")
            #expect(meta[DDTestTags.testType] == "test")
        }
    }

    // Regression coverage for issue #280: a test that fails by *throwing* must
    // make the test process exit non-zero (`success == false`) and be reported
    // as failed — not silently pass.
    @Test func basicThrow() async throws {
        try await run(test: "STBasicThrow/basicThrow()") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == false)
            #expect(spans.count == 1)
            let span = try #require(spans.last)
            let meta = span.meta
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusFail)
            #expect(span.resource == "STBasicThrow.basicThrow")
            #expect(meta[DDTestTags.testName] == "basicThrow")
            #expect(meta[DDTestTags.testSuite] == "STBasicThrow")
            #expect(meta[DDTestTags.testType] == "test")
            #expect(meta[DDTags.errorType] != nil)
            #expect(meta[DDTags.errorMessage] != nil)
        }
    }

    @Test func asynchronousThrow() async throws {
        try await run(test: "STAsynchronousThrow/asynchronousThrow()") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == false)
            #expect(spans.count == 1)
            let span = try #require(spans.last)
            let meta = span.meta
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusFail)
            #expect(span.resource == "STAsynchronousThrow.asynchronousThrow")
            #expect(meta[DDTestTags.testName] == "asynchronousThrow")
            #expect(meta[DDTestTags.testSuite] == "STAsynchronousThrow")
            #expect(meta[DDTestTags.testType] == "test")
            #expect(meta[DDTags.errorType] != nil)
        }
    }

    // Parameterized + throwing: the exact reported shape. Cases value=2 and
    // value=3 throw; value=1 passes. The process must exit non-zero and the two
    // throwing cases must be reported as failed.
    @Test func parameterizedThrow() async throws {
        try await run(test: "STParameterizedThrow/parameterizedThrow(value:)") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == false)
            #expect(spans.count == 3)
            let statuses = spans.compactMap { $0.meta[DDTestTags.testStatus] }.sorted()
            #expect(statuses == [DDTagValues.statusFail, DDTagValues.statusFail, DDTagValues.statusPass])
            for span in spans {
                #expect(span.resource == "STParameterizedThrow.parameterizedThrow(value:)")
                #expect(span.meta[DDTestTags.testSuite] == "STParameterizedThrow")
            }
        }
    }

    @Test func nestedSuitePass() async throws {
        try await run(test: "STNestedSuite/Inner/nestedPass()") { backend, success in
            let spans = backend.allTestSpans
            let suiteEnds = backend.allSuiteEnds
            #expect(success == true)
            #expect(spans.count == 1)
            let span = try #require(spans.last)
            let meta = span.meta
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(span.resource == "STNestedSuite.Inner.nestedPass")
            #expect(meta[DDTestTags.testName] == "nestedPass")
            #expect(meta[DDTestTags.testSuite] == "STNestedSuite.Inner")
            #expect(meta[DDTestTags.testType] == "test")

            // Source location was resolved for the nested test: function-lines
            // lookup keys are `<ddSuite>.<ddName>`, which the FileLocator's
            // last-dot split produces from the dsym symbol
            // `STNestedSuite.Inner.nestedPass()`.
            let sourceFile = meta[DDTestTags.testSourceFile] ?? ""
            #expect(sourceFile.hasSuffix("SwiftTestingSmokeTests.swift"))
            #expect((meta[DDTestTags.testSourceStartLine] ?? "0") != "0")
            #expect((meta[DDTestTags.testSourceEndLine] ?? "0") != "0")

            // Only the leaf suite that actually owns the test should emit a
            // `test_suite_end` event. The outer `STNestedSuite` container
            // should not produce one of its own.
            let emittedSuites = suiteEnds.map(\.resource).sorted()
            #expect(emittedSuites == ["STNestedSuite.Inner"])

            // Exactly one module_end and one session_end should be emitted
            // for a single-test run, regardless of suite nesting.
            #expect(backend.allModuleEnds.count == 1)
            #expect(backend.allSessionEnds.count == 1)
        }
    }

    @Test func networkIntegration() async throws {
        try await run(test: "STNetworkIntegration/networkIntegration()") { backend, success in
            let testSpans = backend.allTestSpans
            let infoSpans = backend.allInfoSpans
            #expect(success == true)
            #expect(testSpans.count == 1)
            #expect(infoSpans.count == 1)
            let testSpan = try #require(testSpans.last)
            let meta = testSpan.meta
            let infoMeta = try #require(infoSpans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(testSpan.resource == "STNetworkIntegration.networkIntegration")
            #expect(meta[DDTestTags.testName] == "networkIntegration")
            #expect(meta[DDTestTags.testSuite] == "STNetworkIntegration")
            #expect(meta[DDTestTags.testType] == "test")
            #expect(infoMeta["http.method"] == "GET")
        }
    }
    
    @Test(
        .disabled(if: XcodeTestRunner.isWatchOSChildSDK,
                  "KSCrash disables signal/mach exception handlers on watchOS (KSCRASH_HAS_SIGNAL = 0, KSCRASH_HAS_MACH = 0), so SIGILL from Swift array bounds traps cannot be captured.")
    )
    func crash() async throws {
        try await run(test: "STCrash") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == false)
            #expect(spans.count == 2)

            let failedSpan = try #require(spans.first)
            let failed = failedSpan.meta
            #expect(failed[DDTestTags.testStatus] == DDTagValues.statusFail)
            #expect(failedSpan.resource == "STCrash.crash")
            #expect(failed[DDTestTags.testName] == "crash")
            #expect(failed[DDTestTags.testSuite] == "STCrash")
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
            #expect(succeededSpan.resource == "STCrash.noCrash")
            #expect(succeeded[DDTestTags.testName] == "noCrash")
            #expect(succeeded[DDTestTags.testSuite] == "STCrash")
            #expect(succeeded[DDTestTags.testType] == "test")
            #expect(succeeded[DDTags.errorType] == nil)
            #expect(succeeded[DDTags.errorMessage] == nil)
            #expect(succeeded[DDTags.errorStack] == nil)
            #expect(succeeded[DDTags.errorCrashLog + ".00"] == nil)
        }
    }

    /// Full-stack integration test against the *stripped* framework: spins up
    /// the real SDK in a subprocess that runs
    /// `STStdoutOTelAndCoverage.stdoutOTelAndCoverage`, then asserts the
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

        try await run(test: "STStdoutOTelAndCoverage/stdoutOTelAndCoverage()", config: config) { backend, success in
            #expect(success == true)

            let spans = backend.allTestSpans
            #expect(spans.count == 1)
            let testSpan = try #require(spans.last)
            #expect(testSpan.meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(testSpan.resource == "STStdoutOTelAndCoverage.stdoutOTelAndCoverage")
            #expect(testSpan.meta[DDTestTags.testName] == "stdoutOTelAndCoverage")
            #expect(testSpan.meta[DDTestTags.testSuite] == "STStdoutOTelAndCoverage")
            #expect(testSpan.meta[DDTestTags.testType] == "test")
            let testSessionId = try #require(testSpan.testSessionId)
            let testModuleId = try #require(testSpan.testModuleId)
            let testSuiteId = try #require(testSpan.testSuiteId)

            let stdoutLog = try #require(backend.allLogs.first { $0.message?.contains("hello from Swift Testing stdout") == true },
                                         "stdout `print()` should be captured and shipped as a log entry")
            #expect(stdoutLog.fields["dd.trace_id"]?.stringValue == String(testSpan.traceId),
                    "stdout log must correlate to the test span via dd.trace_id")
            #expect(stdoutLog.fields["dd.span_id"]?.stringValue == String(testSpan.spanId),
                    "stdout log must correlate to the test span via dd.span_id")

            let coverages = backend.allCoverages
            #expect(!coverages.isEmpty, "at least one coverage payload should arrive for the passing test")
            let coverage = try #require(coverages.first { $0.spanId == testSpan.spanId },
                                        "no coverage payload was associated with the test span")
            #expect(coverage.testSessionId == testSessionId)
            #expect(coverage.testSuiteId == testSuiteId)
            _ = testModuleId
        }
    }
}
