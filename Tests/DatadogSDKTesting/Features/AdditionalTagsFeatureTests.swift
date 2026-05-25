/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting

final class AdditionalTagsSuiteCodeownersTests: XCTestCase {
    private let module = "MyModule"

    private let codeOwnersContent = """
    *               @global
    /Sources/Foo/   @foo-team
    /Sources/Bar/   @bar-team
    /Sources/Baz/   @baz-team
    """

    func testSuiteTagIsSetWhenAllTestsShareOneFile() async throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersContent)
        let bundleFunctions: FunctionMap = [
            "MySuite.testA": .init(file: "/Sources/Foo/A.swift", startLine: 1, endLine: 5),
            "MySuite.testB": .init(file: "/Sources/Foo/A.swift", startLine: 7, endLine: 9),
        ]

        let session = await runSession(bundleFunctions: bundleFunctions, codeOwners: codeOwners,
                                       tests: [module: ["MySuite": ["testA": .pass(), "testB": .pass()]]])

        XCTAssertEqual(session[module]?["MySuite"]?.get(tag: DDTestTags.testCodeowners),
                       "[\"@foo-team\"]")
    }

    func testSuiteTagAggregatesOwnersAcrossFiles() async throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersContent)
        let bundleFunctions: FunctionMap = [
            "MySuite.testA": .init(file: "/Sources/Foo/A.swift", startLine: 1, endLine: 5),
            "MySuite.testB": .init(file: "/Sources/Bar/B.swift", startLine: 1, endLine: 5),
        ]

        let session = await runSession(bundleFunctions: bundleFunctions, codeOwners: codeOwners,
                                       tests: [module: ["MySuite": ["testA": .pass(), "testB": .pass()]]])

        // Owners are accumulated in test-execution order, deduped.
        XCTAssertEqual(session[module]?["MySuite"]?.get(tag: DDTestTags.testCodeowners),
                       "[\"@foo-team\",\"@bar-team\"]")
    }

    func testSuiteTagDedupesRepeatedOwners() async throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersContent)
        let bundleFunctions: FunctionMap = [
            "MySuite.testA": .init(file: "/Sources/Foo/A.swift", startLine: 1, endLine: 5),
            "MySuite.testB": .init(file: "/Sources/Foo/B.swift", startLine: 1, endLine: 5),
            "MySuite.testC": .init(file: "/Sources/Foo/C.swift", startLine: 1, endLine: 5),
        ]

        let session = await runSession(bundleFunctions: bundleFunctions, codeOwners: codeOwners,
                                       tests: [module: ["MySuite": [
                                           "testA": .pass(),
                                           "testB": .pass(),
                                           "testC": .pass(),
                                       ]]])

        XCTAssertEqual(session[module]?["MySuite"]?.get(tag: DDTestTags.testCodeowners),
                       "[\"@foo-team\"]")
    }

    func testSuiteTagIgnoresTestsWithoutFileInfo() async throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersContent)
        // Only the middle test has file info — the suite tag reflects only that file.
        let bundleFunctions: FunctionMap = [
            "MySuite.testB": .init(file: "/Sources/Bar/B.swift", startLine: 1, endLine: 5),
        ]

        let session = await runSession(bundleFunctions: bundleFunctions, codeOwners: codeOwners,
                                       tests: [module: ["MySuite": [
                                           "testA": .pass(),
                                           "testB": .pass(),
                                           "testC": .pass(),
                                       ]]])

        XCTAssertEqual(session[module]?["MySuite"]?.get(tag: DDTestTags.testCodeowners),
                       "[\"@bar-team\"]")
    }

    func testSuiteTagIsNilWhenNoBundleFunctions() async throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersContent)

        let session = await runSession(bundleFunctions: [:], codeOwners: codeOwners,
                                       tests: [module: ["MySuite": ["testA": .pass()]]])

        XCTAssertNil(session[module]?["MySuite"]?.get(tag: DDTestTags.testCodeowners))
    }

    func testSuiteTagIsNilWhenCodeOwnersIsNil() async throws {
        let bundleFunctions: FunctionMap = [
            "MySuite.testA": .init(file: "/Sources/Foo/A.swift", startLine: 1, endLine: 5),
        ]

        let session = await runSession(bundleFunctions: bundleFunctions, codeOwners: nil,
                                       tests: [module: ["MySuite": ["testA": .pass()]]])

        XCTAssertNil(session[module]?["MySuite"]?.get(tag: DDTestTags.testCodeowners))
    }

    func testOwnersAreScopedPerSuite() async throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersContent)
        let bundleFunctions: FunctionMap = [
            "FooSuite.testA": .init(file: "/Sources/Foo/A.swift", startLine: 1, endLine: 5),
            "BarSuite.testB": .init(file: "/Sources/Bar/B.swift", startLine: 1, endLine: 5),
            "BazSuite.testC": .init(file: "/Sources/Baz/C.swift", startLine: 1, endLine: 5),
        ]

        let session = await runSession(bundleFunctions: bundleFunctions, codeOwners: codeOwners,
                                       tests: [module: [
                                           "FooSuite": ["testA": .pass()],
                                           "BarSuite": ["testB": .pass()],
                                           "BazSuite": ["testC": .pass()],
                                       ]])

        XCTAssertEqual(session[module]?["FooSuite"]?.get(tag: DDTestTags.testCodeowners), "[\"@foo-team\"]")
        XCTAssertEqual(session[module]?["BarSuite"]?.get(tag: DDTestTags.testCodeowners), "[\"@bar-team\"]")
        XCTAssertEqual(session[module]?["BazSuite"]?.get(tag: DDTestTags.testCodeowners), "[\"@baz-team\"]")
    }

    // MARK: helpers

    private func runSession(
        bundleFunctions: FunctionMap,
        codeOwners: CodeOwners?,
        tests: Mocks.Runner.Tests
    ) async -> Mocks.Session {
        let feature: TestHooksFeature = AdditionalTags(
            bundleFunctions: bundleFunctions,
            codeOwners: codeOwners
        )
        return await Mocks.Runner(features: [feature], tests: tests).run()
    }
}
