/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public protocol Logger: Sendable {
    var isDebug: Bool { get }
    func print(_ message: String)
    func debug(_ wrapped: @autoclosure () -> String)
    func measure<T, E: Error>(name: String, _ operation: () throws(E) -> T) throws(E) -> T
    func measure<T, E: Error>(name: String, _ operation: @Sendable () async throws(E) -> T) async throws(E) -> T
}

public extension Logger {
    func measure<T>(name: String, _ operation: () -> T) -> T {
        measure(name: name) { () throws(Never) in
            operation()
        }
    }
    
    func measure<T>(name: String, _ operation: @Sendable () async -> T) async -> T {
        await measure(name: name) { () async throws(Never) in
            await operation()
        }
    }
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
