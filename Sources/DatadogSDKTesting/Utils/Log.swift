//
//  Logger.swift
//  Logger
//
//  Created by Ignacio Bonafonte Arruga on 7/10/21.
//

import Foundation

struct Log {
    private static var debugTracer = DDTestMonitor.env.extraDebug

    static func debug(_ string: String) {
        if debugTracer {
            Swift.print("[Debug][DatadogSDKTesting] " + string)
        }
    }

    static func print(_ string: String) {
        Swift.print("[DatadogSDKTesting] " + string)
    }
}
