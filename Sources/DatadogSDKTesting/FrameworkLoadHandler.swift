/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

public class FrameworkLoadHandler: NSObject {
    static var environment = ProcessInfo.processInfo.environment

    @objc
    public static func handleLoad() {
        installTestObserver()
    }

    internal static func installTestObserver() {
        /// Only initialize test observer if user configured so and is running tests
        guard let enabled = environment["DD_TEST_RUNNER"] as NSString? else {
            print("[DatadogSDKTesting] Library loaded but not active, DD_TEST_RUNNER is missing")
            return
        }

        if enabled.boolValue == false {
            print("[DatadogSDKTesting] Library loaded but not active, DD_TEST_RUNNER is off")
            return
        }

        let isInTestMode = environment["XCInjectBundleInto"] != nil ||
            environment["XCTestConfigurationFilePath"] != nil
        if isInTestMode {
            guard environment["DATADOG_CLIENT_TOKEN"] != nil else {
                print("[DatadogSDKTesting] DATADOG_CLIENT_TOKEN missing.")
                return
            }
            if environment["SRCROOT"] == nil {
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
