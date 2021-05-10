/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting

class FrameworkLoadHandlerTests: XCTestCase {
    private var testEnvironment = [String: String]()
    private var previousEnvironment = [String: String]()

    override func setUp() {
        FrameworkLoadHandler.environment = [String: String]()
        DDTestMonitor.instance = nil
        previousEnvironment = DDEnvironmentValues.environment 

    }

    override func tearDownWithError() throws {
        if let monitor = DDTestMonitor.instance,
           let observer = monitor.testObserver {
            XCTestObservationCenter.shared.removeTestObserver(observer)
            DDTestMonitor.instance = nil
        }
        DDEnvironmentValues.environment = previousEnvironment
    }

    func setEnvVariables() {
        FrameworkLoadHandler.environment = testEnvironment
        DDEnvironmentValues.environment = testEnvironment
        DDEnvironmentValues.environment["DD_DONT_EXPORT"] = "true"
        DDEnvironmentValues.environment["DATADOG_CLIENT_TOKEN"] = "fakeToken"
    }

    func testWhenTestRunnerIsConfiguredAndIsInTestingMode_ItIsInitialised() {
        testEnvironment["DD_TEST_RUNNER"] = "1"
        testEnvironment["DD_DISABLE_STDERR_INSTRUMENTATION"] = "1"
        testEnvironment["XCTestConfigurationFilePath"] = "/Users/user/Library/tmp/xx.xctestconfiguration"
        setEnvVariables()

        FrameworkLoadHandler.handleLoad()

        XCTAssertNotNil(DDTestMonitor.instance)
    }

    func testWhenTestRunnerIsConfiguredAndIsInOtherTestingMode_ItIsInitialised() {
        testEnvironment["DD_TEST_RUNNER"] = "1"
        testEnvironment["DD_DISABLE_STDERR_INSTRUMENTATION"] = "1"
        testEnvironment["XCInjectBundleInto"] = "/Users/user/Library/tmp/xx.xctestconfiguration"
        setEnvVariables()

        FrameworkLoadHandler.handleLoad()

        XCTAssertNotNil(DDTestMonitor.instance)
    }

    func testWhenTestRunnerIsNotConfigured_ItIsNotInitialised() {
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
