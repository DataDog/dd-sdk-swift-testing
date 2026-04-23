/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Testing
@testable import DatadogSDKTesting

@Suite("Integration Tests - XCTest Smoke UI Tests",
       .build("UITests", bundle: "Tests"),
       .datadogTesting)
struct UITestsXCTestSmoke: IntergationTestSuite {
    @Test func basicPass() async throws {
        try await run(test: "UIBasicPass/testBasicPass") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == true)
            #expect(spans.count == 1)
            let meta = try #require(spans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(meta[DDGenericTags.resource] == "UIBasicPass.testBasicPass")
            #expect(meta[DDTestTags.testName] == "testBasicPass")
            #expect(meta[DDTestTags.testSuite] == "UIBasicPass")
            #expect(meta[DDTestTags.testType] == "test")
        }
    }

    @Test func basicSkip() async throws {
        try await run(test: "UIBasicSkip/testBasicSkip") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == true)
            #expect(spans.count == 1)
            let meta = try #require(spans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusSkip)
            #expect(meta[DDGenericTags.resource] == "UIBasicSkip.testBasicSkip")
            #expect(meta[DDTestTags.testName] == "testBasicSkip")
            #expect(meta[DDTestTags.testSuite] == "UIBasicSkip")
            #expect(meta[DDTestTags.testType] == "test")
        }
    }

    @Test func basicError() async throws {
        try await run(test: "UIBasicError/testBasicError") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == false)
            #expect(spans.count == 1)
            let meta = try #require(spans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusFail)
            #expect(meta[DDGenericTags.resource] == "UIBasicError.testBasicError")
            #expect(meta[DDTestTags.testName] == "testBasicError")
            #expect(meta[DDTestTags.testSuite] == "UIBasicError")
            #expect(meta[DDTestTags.testType] == "test")
        }
    }

    @Test func environmentPassed() async throws {
        try await run(test: "UIEnvironmentPassed/testEnvironmentPassed") { backend, success in
            let spans = backend.allTestSpans
            #expect(success == true)
            #expect(spans.count == 1)
            let meta = try #require(spans.last?.meta)
            #expect(meta[DDTestTags.testStatus] == DDTagValues.statusPass)
            #expect(meta[DDGenericTags.resource] == "UIEnvironmentPassed.testEnvironmentPassed")
            #expect(meta[DDTestTags.testName] == "testEnvironmentPassed")
            #expect(meta[DDTestTags.testSuite] == "UIEnvironmentPassed")
            #expect(meta[DDTestTags.testType] == "test")
        }
    }
}
