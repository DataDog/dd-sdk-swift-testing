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
        guard let enabled = environment[ConfigurationValues.DD_TEST_RUNNER.rawValue] as NSString? else {
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
            let envEnabledCodeCoverage = environment["DD_CIVISIBILITY_CODE_COVERAGE_ENABLED"] as NSString?
            let envEnabledITR = environment["DD_CIVISIBILITY_ITR_ENABLED"] as NSString?
            if envEnabledCodeCoverage?.boolValue ?? envEnabledITR?.boolValue ?? true,
               let profilePath = environment["LLVM_PROFILE_FILE"]
            {
                let newEnv = profilePath.replacingOccurrences(of: "%c", with: "")
                setenv("LLVM_PROFILE_FILE", newEnv, 1)
            }

            let envDisableTestInstrumenting = DDEnvironmentValues.getEnvVariable(ConfigurationValues.DD_DISABLE_TEST_INSTRUMENTING.rawValue) as NSString?
            let disableTestInstrumenting = envDisableTestInstrumenting?.boolValue ?? false

            let needsTestObserver = !DDTestMonitor.tracer.isBinaryUnderUITesting || environment["TEST_CLASS"] != nil

            if needsTestObserver, !disableTestInstrumenting {
                testObserver = DDTestObserver()
                testObserver?.startObserving()
            } else if DDTestMonitor.tracer.isBinaryUnderUITesting {
                print("[DatadogSDKTesting] Application launched from UITest while being instrumented")
                DDTestMonitor.instance = DDTestMonitor()
                DDTestMonitor.instance?.startInstrumenting()
                DDTestMonitor.instance?.initializationWorkQueue.waitUntilAllOperationsAreFinished()
            }
        } else {
            print("[DatadogSDKTesting] Framework loaded but not in test mode")
        }
    }
}
