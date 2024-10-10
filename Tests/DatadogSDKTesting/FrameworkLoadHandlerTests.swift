/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import XCTest

class FrameworkLoadHandlerTests: XCTestCase {
    override func setUp() {
        XCTAssertNil(DDTracer.activeSpan)
        FrameworkLoadHandler.testObserver?.stop()
        FrameworkLoadHandler.testObserver = nil
        DDTestMonitor.instance = nil
    }

    override func tearDownWithError() throws {
        FrameworkLoadHandler.testObserver?.stop()
        FrameworkLoadHandler.testObserver = nil
        DDTestMonitor._env_recreate()
        DDTestMonitor.instance = DDTestMonitor()
        XCTAssertNil(DDTracer.activeSpan)
    }

    func testWhenTestRunnerIsConfiguredAndIsInTestingMode_ItIsInitialised() {
        setEnv(env: ["DD_TEST_RUNNER": "1", "DD_API_KEY": "fakeToken",
                     "XCTestConfigurationFilePath": "/Users/user/Library/tmp/xx.xctestconfiguration"])

        FrameworkLoadHandler.handleLoad()

        XCTAssertNotNil(FrameworkLoadHandler.testObserver)
    }

    func testWhenTestRunnerIsConfiguredAndIsInOtherTestingMode_ItIsInitialised() {
        setEnv(env: ["DD_TEST_RUNNER": "1", "DD_API_KEY": "fakeToken",
                     "DD_ENABLE_STDERR_INSTRUMENTATION": "1",
                     "XCInjectBundleInto": "/Users/user/Library/tmp/xx.xctestconfiguration"])

        FrameworkLoadHandler.handleLoad()

        XCTAssertNotNil(FrameworkLoadHandler.testObserver)
    }

    func testWhenTestRunnerIsNotConfigured_ItIsNotInitialised() {
        setEnv(env: ["XCInjectBundleInto": "/Users/user/Library/tmp/xx.xctestconfiguration"])

        FrameworkLoadHandler.handleLoad()

        XCTAssertNil(FrameworkLoadHandler.testObserver)
    }

    func testWhenTestRunnerIsConfiguredButSetOff_ItIsNotInitialised() {
        setEnv(env: ["DD_TEST_RUNNER": "0",
                     "XCInjectBundleInto": "/Users/user/Library/tmp/xx.xctestconfiguration"])

        FrameworkLoadHandler.handleLoad()

        XCTAssertNil(FrameworkLoadHandler.testObserver)
    }

    func testWhenTestRunnerIsConfiguredButNotInTestingMode_ItIsNotInitialised() {
        setEnv(env: ["DD_TEST_RUNNER": "1"])
        FrameworkLoadHandler.handleLoad()

        XCTAssertNil(FrameworkLoadHandler.testObserver)
    }
    
    private func setEnv(env: [String: String]) {
        var env = env
        env["DD_ENABLE_STDERR_INSTRUMENTATION"] = "1"
        env["DD_DISABLE_NETWORK_INSTRUMENTATION"] = "1"
        env["DD_DONT_EXPORT"] = "1"
        DDTestMonitor._env_recreate(env: env, patch: false)
    }
}
