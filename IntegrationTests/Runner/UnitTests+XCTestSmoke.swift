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
    
    @Test func crash() async throws {
        try await run(test: "XCCrash/testCrash") { backend, success in
            let testSpans = backend.allTestSpans
            #expect(success == false)
            #expect(testSpans.count == 1)
            let meta = try #require(testSpans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusFail)
            #expect(meta[DDGenericTags.resource] == "XCCrash.testCrash")
            #expect(meta[DDTestTags.testName] == "testCrash")
            #expect(meta[DDTestTags.testSuite] == "XCCrash")
            #expect(meta[DDTestTags.testType] == "test")
            #expect(meta[DDTags.errorType] != nil)
            #expect(meta[DDTags.errorMessage] != nil)
            #expect(meta[DDTags.errorStack] != nil)
            #expect(meta[DDTags.errorCrashLog + ".00"] != nil)
        }
    }
}
