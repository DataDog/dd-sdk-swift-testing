/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest

final class UIBasicPass: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor func testBasicPass() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.exists)
    }
}

final class UIBasicSkip: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor func testBasicSkip() throws {
        throw XCTSkip("skip")
    }
}

final class UIBasicError: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor func testBasicError() {
        XCTAssert(false)
    }
}

final class UIEnvironmentPassed: XCTestCase {
    private static let envKeys = ["DD_ENV", "DD_SERVICE", "DD_API_KEY", "DD_TEST_RUNNER"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor func testEnvironmentPassed() throws {
        let app = XCUIApplication()
        app.launch()
        
        let env = ProcessInfo.processInfo.environment
        for key in Self.envKeys {
            guard let expected = env[key] else { continue }
            let element = app.staticTexts[key]
            XCTAssertTrue(element.waitForExistence(timeout: 5), "\(key) should be visible in app")
            XCTAssertEqual(element.value as? String, expected, "\(key) value mismatch")
        }
    }
}
