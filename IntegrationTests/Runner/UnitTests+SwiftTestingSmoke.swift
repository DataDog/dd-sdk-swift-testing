/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Testing
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
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusSkip)
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
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusSkip)
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
}
