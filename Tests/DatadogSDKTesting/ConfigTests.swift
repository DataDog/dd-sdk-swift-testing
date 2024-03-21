/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting

class ConfigTests: XCTestCase {
    func testWhenDatadogSettingsAreSetInEnvironment_TheyAreStoredCorrectly() {
        var testEnvironment = [String: SpanAttributeConvertible]()
        testEnvironment["DD_API_KEY"] = "token5a101f16"
        testEnvironment["DD_SERVICE"] = "testService"
        testEnvironment["DD_ENV"] = "testEnv"

        let config = Config(env: reader(env: testEnvironment))
        
        XCTAssertEqual(config.apiKey, "token5a101f16")
        XCTAssertEqual(config.environment, "testEnv")
        XCTAssertEqual(config.service, "testService")
    }
    
    func testWhenDatadogSettingsAreSetInInfoPlist_TheyAreStoredCorrectly() {
        var testInfoDictionary = [String: String]()
        testInfoDictionary["DD_API_KEY"] = "token5a101f16"
        testInfoDictionary["DD_SERVICE"] = "testService"
        testInfoDictionary["DD_ENV"] = "testEnv"

        let config = Config(env: reader(info: testInfoDictionary))
        
        XCTAssertEqual(config.apiKey, "token5a101f16")
        XCTAssertEqual(config.environment, "testEnv")
        XCTAssertEqual(config.service, "testService")
    }
    
    func testWhenDatadogSettingsAreSetInEnvironmentAndPlist_EnvironmentTakesPrecedence() {
        var testEnvironment = [String: SpanAttributeConvertible]()
        testEnvironment["DD_API_KEY"] = "token5a101f16"
        testEnvironment["DD_SERVICE"] = "testService"
        testEnvironment["DD_ENV"] = "testEnv"

        var testInfoDictionary = [String: String]()
        testInfoDictionary["DD_API_KEY"] = "token5a101f162"
        testInfoDictionary["DD_SERVICE"] = "testService2"
        testInfoDictionary["DD_ENV"] = "testEnv2"

        let config = Config(env: reader(env: testEnvironment, info: testInfoDictionary))
        XCTAssertEqual(config.apiKey, "token5a101f16")
        XCTAssertEqual(config.environment, "testEnv")
        XCTAssertEqual(config.service, "testService")
    }

    func testWhenNoConfigurationEnvironmentAreSet_DefaultValuesAreUsed() {
        let config = Config(env: reader())
        XCTAssertEqual(config.disableNetworkInstrumentation, false)
        XCTAssertEqual(config.enableStdoutInstrumentation, false)
        XCTAssertEqual(config.enableStderrInstrumentation, false)
        XCTAssertEqual(config.disableHeadersInjection, false)
        XCTAssertEqual(config.extraHTTPHeaders, nil)
        XCTAssertEqual(config.excludedURLS, nil)
        XCTAssertEqual(config.enableRecordPayload, false)
        XCTAssertEqual(config.disableCrashHandler, false)
    }

    func testWhenConfigurationEnvironmentAreSet_TheyAreStoredCorrectly() {
        var testEnvironment = [String: SpanAttributeConvertible]()
        testEnvironment["DD_DISABLE_NETWORK_INSTRUMENTATION"] = "1"
        testEnvironment["DD_ENABLE_STDOUT_INSTRUMENTATION"] = "yes"
        testEnvironment["DD_ENABLE_STDERR_INSTRUMENTATION"] = "true"
        testEnvironment["DD_DISABLE_HEADERS_INJECTION"] = "YES"
        testEnvironment["DD_INSTRUMENTATION_EXTRA_HEADERS"] = "header1,header2;header3 header4"
        testEnvironment["DD_EXCLUDED_URLS"] = "http://www.google"
        testEnvironment["DD_ENABLE_RECORD_PAYLOAD"] = "true"
        testEnvironment["DD_DISABLE_CRASH_HANDLER"] = "true"
        
        let config = Config(env: reader(env: testEnvironment))

        XCTAssertEqual(config.disableNetworkInstrumentation, true)
        XCTAssertEqual(config.enableStdoutInstrumentation, true)
        XCTAssertEqual(config.enableStderrInstrumentation, true)
        XCTAssertEqual(config.disableHeadersInjection, true)
        XCTAssertEqual(config.extraHTTPHeaders?.count, 4)
        XCTAssertEqual(config.excludedURLS?.count, 1)
        XCTAssertEqual(config.enableRecordPayload, true)
        XCTAssertEqual(config.disableCrashHandler, true)
    }

    func testWhenConfigurationPListAreSet_TheyAreStoredCorrectly() {
        var testInfoDictionary = [String: String]()
        testInfoDictionary["DD_DISABLE_NETWORK_INSTRUMENTATION"] = "1"
        testInfoDictionary["DD_ENABLE_STDOUT_INSTRUMENTATION"] = "yes"
        testInfoDictionary["DD_ENABLE_STDERR_INSTRUMENTATION"] = "true"
        testInfoDictionary["DD_DISABLE_HEADERS_INJECTION"] = "YES"
        testInfoDictionary["DD_INSTRUMENTATION_EXTRA_HEADERS"] = "header1,header2;header3 header4"
        testInfoDictionary["DD_EXCLUDED_URLS"] = "http://www.google"
        testInfoDictionary["DD_ENABLE_RECORD_PAYLOAD"] = "true"
        testInfoDictionary["DD_DISABLE_CRASH_HANDLER"] = "true"
        
        let config = Config(env: reader(info: testInfoDictionary))

        XCTAssertEqual(config.disableNetworkInstrumentation, true)
        XCTAssertEqual(config.enableStdoutInstrumentation, true)
        XCTAssertEqual(config.enableStderrInstrumentation, true)
        XCTAssertEqual(config.disableHeadersInjection, true)
        XCTAssertEqual(config.extraHTTPHeaders?.count, 4)
        XCTAssertEqual(config.excludedURLS?.count, 1)
        XCTAssertEqual(config.enableRecordPayload, true)
        XCTAssertEqual(config.disableCrashHandler, true)
    }

    func testWhenConfigurationEnvironmentAndPListAreSet_EnvironmentTakesPrecedence() {
        var testEnvironment = [String: SpanAttributeConvertible]()
        testEnvironment["DD_DISABLE_NETWORK_INSTRUMENTATION"] = "1"
        testEnvironment["DD_ENABLE_STDOUT_INSTRUMENTATION"] = "yes"
        testEnvironment["DD_ENABLE_STDERR_INSTRUMENTATION"] = "true"
        testEnvironment["DD_DISABLE_HEADERS_INJECTION"] = "YES"
        testEnvironment["DD_INSTRUMENTATION_EXTRA_HEADERS"] = "header1,header2;header3 header4"
        testEnvironment["DD_EXCLUDED_URLS"] = "http://www.google"
        testEnvironment["DD_ENABLE_RECORD_PAYLOAD"] = "true"
        testEnvironment["DD_DISABLE_CRASH_HANDLER"] = "true"

        var testInfoDictionary = [String: String]()
        testInfoDictionary["DD_DISABLE_NETWORK_INSTRUMENTATION"] = "0"
        testInfoDictionary["DD_ENABLE_STDOUT_INSTRUMENTATION"] = "no"
        testInfoDictionary["DD_ENABLE_STDERR_INSTRUMENTATION"] = "false"
        testInfoDictionary["DD_DISABLE_HEADERS_INJECTION"] = "NO"
        testInfoDictionary["DD_INSTRUMENTATION_EXTRA_HEADERS"] = "header1,header2"
        testInfoDictionary["DD_EXCLUDED_URLS"] = "http://www.microsoft.com"
        testInfoDictionary["DD_ENABLE_RECORD_PAYLOAD"] = "false"
        testInfoDictionary["DD_DISABLE_CRASH_HANDLER"] = "false"

        let config = Config(env: reader(env: testEnvironment, info: testInfoDictionary))
        XCTAssertEqual(config.disableNetworkInstrumentation, true)
        XCTAssertEqual(config.enableStdoutInstrumentation, true)
        XCTAssertEqual(config.enableStderrInstrumentation, true)
        XCTAssertEqual(config.disableHeadersInjection, true)
        XCTAssertEqual(config.extraHTTPHeaders?.count, 4)
        XCTAssertEqual(config.excludedURLS?.count, 1)
        XCTAssertEqual(config.enableRecordPayload, true)
        XCTAssertEqual(config.disableCrashHandler, true)
    }
    
    private func reader(env: [String: SpanAttributeConvertible] = [:], info: [String: String] = [:]) -> EnvironmentReader {
        ProcessEnvironmentReader(environment: env.mapValues { $0.spanAttribute }, infoDictionary: info)
    }
}
