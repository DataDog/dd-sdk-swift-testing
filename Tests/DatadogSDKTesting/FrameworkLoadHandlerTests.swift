/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

@testable import DatadogSDKTesting
import XCTest

class FrameworkLoadHandlerTests: XCTestCase {
    private var testEnvironment = [String: String]()
    private var previousEnvironment = [String: String]()

    override func setUp() {
        XCTAssertNil(DDTracer.activeSpan)
        FrameworkLoadHandler.environment = [String: String]()
        DDTestMonitor.instance = nil
        previousEnvironment = DDEnvironmentValues.environment
        testEnvironment["DD_DISABLE_TEST_OBSERVER"] = "1"
        testEnvironment["DD_DISABLE_STDERR_INSTRUMENTATION"] = "1"
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
        testEnvironment["DATADOG_CLIENT_TOKEN"] = "fakeToken"
        testEnvironment["XCTestConfigurationFilePath"] = "/Users/user/Library/tmp/xx.xctestconfiguration"
        setEnvVariables()

        FrameworkLoadHandler.handleLoad()

        XCTAssertNotNil(DDTestMonitor.instance)
    }

    func testWhenTestRunnerIsConfiguredAndIsInOtherTestingMode_ItIsInitialised() {
        testEnvironment["DD_TEST_RUNNER"] = "1"
        testEnvironment["DD_API_KEY"] = "fakeKey"
        testEnvironment["DD_DISABLE_STDERR_INSTRUMENTATION"] = "1"
        testEnvironment["XCInjectBundleInto"] = "/Users/user/Library/tmp/xx.xctestconfiguration"
        setEnvVariables()

        FrameworkLoadHandler.handleLoad()

        XCTAssertNotNil(DDTestMonitor.instance)
    }

    func testWhenTestRunnerIsConfiguredAndIsInTestingModeButNoToken_ItIsNotInitialised() {
        testEnvironment["DD_TEST_RUNNER"] = "1"
        testEnvironment["XCTestConfigurationFilePath"] = "/Users/user/Library/tmp/xx.xctestconfiguration"
        setEnvVariables()

        FrameworkLoadHandler.handleLoad()

        XCTAssertNil(DDTestMonitor.instance)
    }

    func testWhenTestRunnerIsNotConfigured_ItIsNotInitialised() {
        testEnvironment["XCInjectBundleInto"] = "/Users/user/Library/tmp/xx.xctestconfiguration"
        setEnvVariables()

        FrameworkLoadHandler.handleLoad()

        XCTAssertNil(DDTestMonitor.instance)
    }

    func testWhenTestRunnerIsConfiguredButSetOff_ItIsNotInitialised() {
        testEnvironment["DD_TEST_RUNNER"] = "0"
        testEnvironment["XCInjectBundleInto"] = "/Users/user/Library/tmp/xx.xctestconfiguration"
        setEnvVariables()

        FrameworkLoadHandler.handleLoad()

        XCTAssertNil(DDTestMonitor.instance)
    }

    func testWhenTestRunnerIsConfiguredButNotInTestingMode_ItIsNotInitialised() {
        testEnvironment["DD_TEST_RUNNER"] = "1"
        setEnvVariables()
        FrameworkLoadHandler.handleLoad()

        XCTAssertNil(DDTestMonitor.instance)
    }
}
