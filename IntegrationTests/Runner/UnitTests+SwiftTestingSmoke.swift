/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

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
    
    @Test func crash() async throws {
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
}
