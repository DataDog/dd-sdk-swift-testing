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
            let meta = try #require(spans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(meta[DDGenericTags.resource] == "STBasicPass.basicPass")
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
            let meta = try #require(spans.last?.meta)
            #if compiler(>=6.3)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusSkip)
            #else
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #endif
            #expect(meta[DDGenericTags.resource] == "STBasicSkip.basicSkip")
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
            let meta = try #require(spans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusFail)
            #expect(meta[DDGenericTags.resource] == "STBasicError.basicError")
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
            let meta = try #require(spans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(meta[DDGenericTags.resource] == "STAsynchronousPass.asynchronousPass")
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
            let meta = try #require(spans.last?.meta)
            #if compiler(>=6.3)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusSkip)
            #else
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #endif
            #expect(meta[DDGenericTags.resource] == "STAsynchronousSkip.asynchronousSkip")
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
            let meta = try #require(spans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusFail)
            #expect(meta[DDGenericTags.resource] == "STAsynchronousError.asynchronousError")
            #expect(meta[DDTestTags.testName] == "asynchronousError")
            #expect(meta[DDTestTags.testSuite] == "STAsynchronousError")
            #expect(meta[DDTestTags.testType] == "test")
        }
    }

    @Test func nestedSuitePass() async throws {
        try await run(test: "STNestedSuite/Inner/nestedPass()") { backend, success in
            let spans = backend.allTestSpans
            let suiteEnds = backend.allSuiteEnds
            #expect(success == true)
            #expect(spans.count == 1)
            let meta = try #require(spans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(meta[DDGenericTags.resource] == "STNestedSuite.Inner.nestedPass")
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
            let meta = try #require(testSpans.last?.meta)
            let span = try #require(infoSpans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(meta[DDGenericTags.resource] == "STNetworkIntegration.networkIntegration")
            #expect(meta[DDTestTags.testName] == "networkIntegration")
            #expect(meta[DDTestTags.testSuite] == "STNetworkIntegration")
            #expect(meta[DDTestTags.testType] == "test")
            #expect(span["http.method"] == "GET")
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
            
            let failed = try #require(spans.first?.meta)
            #expect(failed[DDTestTags.testStatus] == DDTagValues.statusFail)
            #expect(failed[DDGenericTags.resource] == "STCrash.crash")
            #expect(failed[DDTestTags.testName] == "crash")
            #expect(failed[DDTestTags.testSuite] == "STCrash")
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
            #expect(succeeded[DDGenericTags.resource] == "STCrash.noCrash")
            #expect(succeeded[DDTestTags.testName] == "noCrash")
            #expect(succeeded[DDTestTags.testSuite] == "STCrash")
            #expect(succeeded[DDTestTags.testType] == "test")
            #expect(succeeded[DDTags.errorType] == nil)
            #expect(succeeded[DDTags.errorMessage] == nil)
            #expect(succeeded[DDTags.errorStack] == nil)
            #expect(succeeded[DDTags.errorCrashLog + ".00"] == nil)
        }
    }

    /// Full-stack integration test: spins up the real SDK in a subprocess that
    /// runs `STStdoutOTelAndCoverage.stdoutOTelAndCoverage`, then asserts that
    /// all three telemetry pipelines reached the backend with the right shape:
    /// one test span, the stdout-captured `print()` as a log entry, the OTel
    /// `LogRecord` as a log entry (status `warn`), and at least one coverage
    /// payload.
    @Test func stdoutOTelAndCoverage() async throws {
        var config = XcodeTestRunner.Config()
        config.backend.settings.itrEnabled = true
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
            #expect(testSpan.meta[DDGenericTags.resource] == "STStdoutOTelAndCoverage.stdoutOTelAndCoverage")
            #expect(testSpan.meta[DDTestTags.testName] == "stdoutOTelAndCoverage")
            #expect(testSpan.meta[DDTestTags.testSuite] == "STStdoutOTelAndCoverage")
            #expect(testSpan.meta[DDTestTags.testType] == "test")
            let testSessionId = try #require(testSpan.testSessionId)
            let testModuleId = try #require(testSpan.testModuleId)
            let testSuiteId = try #require(testSpan.testSuiteId)

            let stdoutLog = try #require(backend.allLogs.first { $0.message?.contains("hello from Swift Testing stdout") == true },
                                         "stdout `print()` should be captured and shipped as a log entry")
            let otelLog = try #require(backend.allLogs.first { $0.message?.contains("hello from Swift Testing OTel") == true },
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
