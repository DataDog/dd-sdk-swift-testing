/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public protocol Logger {
    var isDebug: Bool { get }
    func print(_ message: String)
    func debug(_ wrapped: @autoclosure () -> String)
    func measure<T>(name: String, _ operation: () throws -> T) rethrows -> T
    func measureAsync<T, E>(name: String, _ operation: () -> AsyncResult<T, E>) -> AsyncResult<T, E>
}

struct Log {
    private static var _logger: Logger? = nil
    
    static var isDebug: Bool {
        _logger?.isDebug ?? false
    }
    
    static func setLogger(_ logger: Logger) {
        _logger = logger
    }

    static func debug(_ string: @autoclosure () -> String) {
        _logger?.debug(string())
    }

    static func print(_ string: String) {
        _logger?.print(string)
    }

    static func runOnDebug(_ function: @autoclosure () -> Void) {
        if _logger?.isDebug ?? false {
            function()
        }
    }
}
