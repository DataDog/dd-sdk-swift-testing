/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import CDatadogSDKTesting

enum FrameworkLoadHandler {
    static var testObserver: DDTestObserver?
    
    public static func handleLoad() {
        libraryLoaded()
    }

    fileprivate static func libraryLoaded() {
        let config = DDTestMonitor.config
        /// Only initialize test observer if user configured so and is running tests
        guard let enabled = config.isEnabled else {
            NSLog("[DatadogSDKTesting] Library loaded but not active, DD_TEST_RUNNER is missing")
            return
        }

        guard enabled else {
            NSLog("[DatadogSDKTesting] Library loaded but not active, DD_TEST_RUNNER is off")
            return
        }

        if config.isInTestMode {
            // When code coverage is enabled modify profile name so it disables countinuous profiling
            // or we cannot recover coverage manually
            if config.coverageEnabled || config.itrEnabled,
               let profilePath = DDTestMonitor.envReader["LLVM_PROFILE_FILE", String.self]
            {
                let newEnv = profilePath.replacingOccurrences(of: "%c", with: "")
                setenv("LLVM_PROFILE_FILE", newEnv, 1)
            }
            
            if config.isTestObserverNeeded && !config.disableTestInstrumenting {
                testObserver = DDTestObserver()
                testObserver?.startObserving()
                DispatchQueue.global().async {
                    try! DDTestMonitor.clock.sync()
                }
            } else if config.isBinaryUnderUITesting {
                NSLog("[DatadogSDKTesting] Application launched from UITest while being instrumented")
                DDTestMonitor.instance = DDTestMonitor()
                DDTestMonitor.instance?.startInstrumenting()
                DDTestMonitor.instance?.instrumentationWorkQueue.waitUntilAllOperationsAreFinished()
            }
        } else {
            NSLog("[DatadogSDKTesting] Framework loaded but not in test mode")
        }
    }
    
    // this method should not be called. It's needed for linking
    static func __noop() { AutoLoadHandler() }
}

@_cdecl("__AutoLoadHook")
internal func __AutoLoadHook() {
    FrameworkLoadHandler.libraryLoaded()
}
