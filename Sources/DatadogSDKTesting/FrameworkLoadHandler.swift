/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import CDatadogSDKTesting

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
            if config.isTestObserverNeeded && !config.disableTestInstrumenting {
                testObserver = DDTestObserver()
                testObserver?.start()
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
    
    fileprivate static func libraryUnloaded() {
        testObserver?.stop()
        testObserver = nil
    }
}

@_cdecl("__AutoLoadHook")
internal func __AutoLoadHook() {
    FrameworkLoadHandler.libraryLoaded()
}

@_cdecl("__AutoUnloadHook")
internal func __AutoUnloadHook() {
    FrameworkLoadHandler.libraryUnloaded()
}

// Don't delete this. It simply tells compiler not to remove AutoLoadHandler from binary
// This method can be called from C only. Swift will hide it
@_cdecl("__load_handler__")
internal func __load_handler__() {
    AutoLoadHandler()
    AutoUnloadHandler()
}
