/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import XCTest
import OpenTelemetrySdk

class TestRunner: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {}

    func testBasicPass() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TEST_CLASS"] = "TestRunner.BasicPass"
        app.launch()
    }

    func testBasicSkip() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TEST_CLASS"] = "TestRunner.BasicSkip"
        app.launch()

    }

    func testBasicError() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TEST_CLASS"] = "TestRunner.BasicError"
        app.launch()
    }

    func testAsynchronousPass() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TEST_CLASS"] = "TestRunner.AsynchronousPass"
        app.launch()
    }

    func testAsynchronousSkip() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TEST_CLASS"] = "TestRunner.AsynchronousSkip"
        app.launch()

    }

    func testAsynchronousError() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TEST_CLASS"] = "TestRunner.AsynchronousError"
        app.launch()
    }

    func testBasicNetwork() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TEST_CLASS"] = "TestRunner.BasicNetwork"
        app.launch()
    }
}
