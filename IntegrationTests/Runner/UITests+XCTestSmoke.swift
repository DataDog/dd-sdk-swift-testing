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
