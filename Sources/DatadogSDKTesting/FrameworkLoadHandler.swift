/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

public class FrameworkLoadHandler: NSObject {
    static var environment = ProcessInfo.processInfo.environment
    static var testObserver: DDTestObserver?

    override private init() {}

    @objc
    public static func handleLoad() {
        libraryLoaded()
    }

    static func libraryLoaded() {
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
            environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTestBundlePath"] != nil ||
            environment["SDKROOT"] != nil
        if isInTestMode {
            if !DDTestMonitor.tracer.isBinaryUnderUITesting {
                if !DDTestMonitor.env.disableTestInstrumenting {
                    DDTestObserver().startObserving()
                }
            } else {
                /// If the library is being loaded in a binary launched from a UITest, dont start test observing,
                /// except if testing the tracer itself
                if DDTestMonitor.env.tracerUnderTesting {
                    testObserver = DDTestObserver()
                    testObserver?.startObserving()
                }
            }

            let envDisableTestInstrumenting = DDEnvironmentValues.getEnvVariable("DD_DISABLE_TEST_INSTRUMENTING") as NSString?
            let disableTestInstrumenting = envDisableTestInstrumenting?.boolValue ?? false
            if !disableTestInstrumenting {
                testObserver = DDTestObserver()
                testObserver?.startObserving()
            }
        }
    }
}
