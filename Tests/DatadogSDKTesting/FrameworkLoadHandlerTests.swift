/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import XCTest

class FrameworkLoadHandlerTests: XCTestCase {
    private var testEnvironment = [String: String]()
    private var previousEnvironment = [String: String]()

    override func setUp() {
        XCTAssertNil(DDTracer.activeSpan)
        FrameworkLoadHandler.testObserver = nil
        FrameworkLoadHandler.environment = [String: String]()
        DDTestMonitor.instance = nil
        previousEnvironment = DDEnvironmentValues.environment
        testEnvironment["DD_ENABLE_STDERR_INSTRUMENTATION"] = "1"
        testEnvironment["DD_DISABLE_NETWORK_INSTRUMENTATION"] = "1"
    }

    override func tearDownWithError() throws {
        DDEnvironmentValues.environment = previousEnvironment
        XCTAssertNil(DDTracer.activeSpan)
    }

    func setEnvVariables() {
        FrameworkLoadHandler.environment = testEnvironment
        DDEnvironmentValues.environment = testEnvironment
        DDEnvironmentValues.environment["DD_DONT_EXPORT"] = "true"
        DDTestMonitor.env = DDEnvironmentValues()
    }

    func testWhenTestRunnerIsConfiguredAndIsInTestingMode_ItIsInitialised() {
        testEnvironment["DD_TEST_RUNNER"] = "1"
        testEnvironment[ConfigurationValues.DD_API_KEY.rawValue] = "fakeToken"
        testEnvironment["XCTestConfigurationFilePath"] = "/Users/user/Library/tmp/xx.xctestconfiguration"
        setEnvVariables()

        FrameworkLoadHandler.handleLoad()

        XCTAssertNotNil(FrameworkLoadHandler.testObserver)
    }

    func testWhenTestRunnerIsConfiguredAndIsInOtherTestingMode_ItIsInitialised() {
        testEnvironment["DD_TEST_RUNNER"] = "1"
        testEnvironment[ConfigurationValues.DD_API_KEY.rawValue] = "fakeKey"
        testEnvironment["DD_ENABLE_STDERR_INSTRUMENTATION"] = "1"
        testEnvironment["XCInjectBundleInto"] = "/Users/user/Library/tmp/xx.xctestconfiguration"
        setEnvVariables()

        FrameworkLoadHandler.handleLoad()

        XCTAssertNotNil(FrameworkLoadHandler.testObserver)
    }

    func testWhenTestRunnerIsNotConfigured_ItIsNotInitialised() {
        testEnvironment["XCInjectBundleInto"] = "/Users/user/Library/tmp/xx.xctestconfiguration"
        setEnvVariables()

        FrameworkLoadHandler.handleLoad()

        XCTAssertNil(FrameworkLoadHandler.testObserver)
    }

    func testWhenTestRunnerIsConfiguredButSetOff_ItIsNotInitialised() {
        testEnvironment["DD_TEST_RUNNER"] = "0"
        testEnvironment["XCInjectBundleInto"] = "/Users/user/Library/tmp/xx.xctestconfiguration"
        setEnvVariables()

        FrameworkLoadHandler.handleLoad()

        XCTAssertNil(FrameworkLoadHandler.testObserver)
    }

    func testWhenTestRunnerIsConfiguredButNotInTestingMode_ItIsNotInitialised() {
        testEnvironment["DD_TEST_RUNNER"] = "1"
        setEnvVariables()
        FrameworkLoadHandler.handleLoad()

        XCTAssertNil(FrameworkLoadHandler.testObserver)
    }
}
