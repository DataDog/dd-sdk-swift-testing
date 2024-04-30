/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import EventsExporter

class Log: Logger {
    var isDebug: Bool
    
    init(isDebug: Bool = true) {
        self.isDebug = isDebug
    }
    
    func print(_ message: String) { Swift.print("[LOG] " + message) }
    
    func debug(_ wrapped: @autoclosure () -> String) {
        if isDebug {
            Swift.print("[LOG][D] " + wrapped())
        }
    }
    
    func measure<T>(name: String, _ operation: () throws -> T) rethrows -> T {
        try operation()
    }
}
