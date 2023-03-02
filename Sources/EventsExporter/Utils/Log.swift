/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

struct Log {
    static var debugMode = false

    static func debug(_ string: @autoclosure () -> String) {
        if debugMode {
            NSLog("[Debug][DatadogSDKTesting] " + string() + "\n")
        }
    }

    static func print(_ string: String) {
        if debugMode {
            NSLog("[DatadogSDKTesting] " + string + "\n")
        } else {
            Swift.print("[DatadogSDKTesting] " + string + "\n")
        }
    }

    static func runOnDebug(_ function: @autoclosure () -> Void) {
        if debugMode {
            function()
        }
    }
}
