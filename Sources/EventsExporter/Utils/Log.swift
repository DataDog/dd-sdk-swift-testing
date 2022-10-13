//
//  Logger.swift
//  Logger
//
//  Created by Ignacio Bonafonte Arruga on 7/10/21.
//

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
