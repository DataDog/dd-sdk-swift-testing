//
//  Logger.swift
//  Logger
//
//  Created by Ignacio Bonafonte Arruga on 7/10/21.
//

import Foundation

struct Log {
    private static var debugTracer = DDTestMonitor.env.extraDebug

    static func debug(_ string: @autoclosure () -> String) {
        if debugTracer {
            NSLog("[Debug][DatadogSDKTesting] " + string() + "\n")
        }
    }

    static func print(_ string: String) {
        NSLog("[DatadogSDKTesting] " + string + "\n")
    }
}
