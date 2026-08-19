/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest

final class UIEnvironmentPassed: XCTestCase {
    private static let envKeys = ["DD_ENV", "DD_SERVICE", "DD_API_KEY", "DD_TEST_RUNNER"]

    /// Launching the app takes 60–90s on the visionOS simulator in CI, and the
    /// harness reports `Unable to monitor event loop` while it comes up. These
    /// timeouts are sized for that worst case; they cost nothing on faster
    /// platforms, where both waits return as soon as the app is ready.
    private static let launchTimeout: TimeInterval = 180
    private static let elementTimeout: TimeInterval = 30

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor func testEnvironmentPassed() throws {
        #if os(visionOS)
            // Disabled on visionOS: the app under test cannot be driven by
            // XCUITest there. The SDK adds ~49s to app launch on this platform
            // (measured locally on an idle machine: the app reaches idle in 3.7s
            // with the SDK inactive vs 52.5s with it active, ~14s of that the
            // crash handler). On CI that overruns accessibility-server
            // registration, so every element query fails outright with
            // `kAXErrorServerNotFound` and no timeout can help. This test only
            // checks that the DD_* environment reaches the app, which the other
            // four platforms already cover. Re-enable once app launch is cheap
            // enough for the harness to attach.
            throw XCTSkip("Unsupported on visionOS: app launch overruns accessibility setup")
        #endif

        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }

        // `launch()` returning does not mean the UI exists yet. Without this the
        // element queries below start against an app that is still launching, and
        // a slow simulator turns that into a spurious "not visible" failure.
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: Self.launchTimeout),
                      "App did not reach the foreground within \(Self.launchTimeout)s (state: \(app.state.rawValue))")

        let env = ProcessInfo.processInfo.environment
        for key in Self.envKeys {
            guard let expected = env[key] else { continue }
            let element = app.staticTexts[key]
            XCTAssertTrue(element.waitForExistence(timeout: Self.elementTimeout),
                          "\(key) should be visible in app")
            XCTAssertEqual(element._textValue, expected, "\(key) value mismatch")
        }
    }
}

extension XCUIElementAttributes {
    var _textValue: String {
        if let text = self.value as? String, text != "" {
            return text
        }
        if self.label != "" {
            return self.label
        }
        if self.title != "" {
            return self.title
        }
        return ""
    }
}
