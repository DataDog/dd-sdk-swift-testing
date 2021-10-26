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
            // When code coverage is enabled modify profile name so it disables countinuous profiling
            // or we cannot recover coverage manually
            let envDisableCodeCoverage = environment["DD_DISABLE_CODE_COVERAGE"] as NSString?
            if !(envDisableCodeCoverage?.boolValue ?? false),
               let profilePath = environment["LLVM_PROFILE_FILE"]
            {
                let newEnv = profilePath.replacingOccurrences(of: "%c", with: "")
                setenv("LLVM_PROFILE_FILE", newEnv, 1)
            }

            let envDisableTestInstrumenting = DDEnvironmentValues.getEnvVariable("DD_DISABLE_TEST_INSTRUMENTING") as NSString?
            let disableTestInstrumenting = envDisableTestInstrumenting?.boolValue ?? false

            let needsTestObserver = !DDTestMonitor.tracer.isBinaryUnderUITesting || DDTestMonitor.env.tracerUnderTesting

            if needsTestObserver, !disableTestInstrumenting {
                testObserver = DDTestObserver()
                testObserver?.startObserving()
            } else if DDTestMonitor.tracer.isBinaryUnderUITesting {
                print("[DatadogSDKTesting] Application launched from UITest while being instrumented")
                DDTestMonitor.instance = DDTestMonitor()
                DDTestMonitor.instance?.startInstrumenting()
            }
        }
    }
}
