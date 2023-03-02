/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

struct Log {
    private static var debugTracer = DDTestMonitor.env.extraDebug
    private static var debugTracerCallstack = DDTestMonitor.env.extraDebugCallstack

    private static func swiftPrint(_ string: String) {
        Swift.print(string)
    }

    private static func nslogPrint(_ string: String) {
        NSLog(string)
    }

    private static var printMethod: () -> (String) -> Void = {
        let osActivityMode = DDEnvironmentValues.getEnvVariable("OS_ACTIVITY_MODE") ?? ""
        if osActivityMode == "disable" {
            return swiftPrint
        } else {
            return nslogPrint
        }
    }

    static func debug(_ string: @autoclosure () -> String) {
        if debugTracer {
            Log.printMethod()("[Debug][DatadogSDKTesting] " + string() + "\n")
            if debugTracerCallstack {
                Swift.print("Callstack:\n" + DDSymbolicator.getCallStack(hidesLibrarySymbols: false).joined(separator: "\n") + "\n")
            }
        }
    }

    static func print(_ string: String) {
        Log.printMethod()("[DatadogSDKTesting] " + string + "\n")
    }

    static func measure(name: String, _ operation: () -> Void) {
        if debugTracer {
            let startTime = CFAbsoluteTimeGetCurrent()
            operation()
            let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
            Log.printMethod()("[Debug][DatadogSDKTesting] Time elapsed for \(name): \(timeElapsed) s.")
        } else {
            operation()
        }
    }
    
    static func runOnDebug(_ function: @autoclosure () -> Void) {
        if debugTracer {
            function()
        }
    }
}
