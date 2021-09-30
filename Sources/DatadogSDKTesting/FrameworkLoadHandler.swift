/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

public class FrameworkLoadHandler: NSObject {
    static var environment = ProcessInfo.processInfo.environment

    private override init() {}

    @objc
    public static func handleLoad() {
        installTestMonitor()
    }

    static func installTestMonitor() {
        /// Only initialize test observer if user configured so and is running tests
         guard let enabled = DDEnvironmentValues.getEnvVariable("DD_TEST_RUNNER") as NSString? else {
            print("[DatadogSDKTesting] Library loaded but not active, DD_TEST_RUNNER is missing")
            return
        }

        if enabled.boolValue == false {
            print("[DatadogSDKTesting] Library loaded but not active, DD_TEST_RUNNER is off")
            return
        }

        let isInTestMode = environment["XCInjectBundleInto"] != nil ||
            environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTestBundlePath"] != nil ||
            environment["SDKROOT"] != nil
        if isInTestMode {
            guard DDEnvironmentValues.getEnvVariable("DATADOG_CLIENT_TOKEN") != nil || DDEnvironmentValues.getEnvVariable("DD_API_KEY") != nil else {
                print("[DatadogSDKTesting] DATADOG_CLIENT_TOKEN or DD_API_KEY are missing.")
                return
            }
            if DDEnvironmentValues.getEnvVariable("SRCROOT") == nil {
                print("[DatadogSDKTesting] SRCROOT is not properly set")
            }
            print("[DatadogSDKTesting] Library loaded and active. Instrumenting tests.")
            DDTestMonitor.instance = DDTestMonitor()
            DDTestMonitor.instance?.startInstrumenting()
        } else {
            print("[DatadogSDKTesting] Library loaded but not in testing mode.")
        }
    }
}
