/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

final class Log: Logger {
    var isDebug: Bool = false
    var isDebugTracerCallStack: Bool
    let isSwiftPrint: Bool
    
    init(env: EnvironmentReader) {
        //isSwiftPrint = (env["OS_ACTIVITY_MODE"] ?? "") == "disable"
        isSwiftPrint = true
        isDebug = false
        isDebugTracerCallStack = false
    }
    
    func print(_ message: String) {
        print(prefix: "[DatadogSDKTesting] ", message: message)
    }
    
    func debug(_ wrapped: @autoclosure () -> String) {
        if isDebug {
            print(prefix: "[Debug][DatadogSDKTesting] ", message: wrapped())
            if isDebugTracerCallStack, let symb = symbolicator {
                let stack = symb.getCallStack(hidesLibrarySymbols: false).joined(separator: "\n")
                print(prefix: "CallStack:\n", message: stack)
            }
        }
    }
    
    func measure<T>(name: String, _ operation: () throws -> T) rethrows -> T {
        if isDebug {
            let startTime = CFAbsoluteTimeGetCurrent()
            defer {
                let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
                print(prefix: "[Debug][DatadogSDKTesting] ", message: "Time elapsed for \(name): \(timeElapsed) s.")
            }
            return try operation()
        } else {
            return try operation()
        }
    }

    private func print(prefix: String, message: String) {
        let msg = "note: \(prefix)\(message.replacingOccurrences(of: "\n", with: "\nnote: "))"
        if isSwiftPrint { Swift.print(msg) } else { NSLog(msg) }
    }
}

// TODO: Refactor lib for proper bootstrap and remove this extension
extension Log {
    private var symbolicator: DDSymbolicator.Type? { DDSymbolicator.self }
    static var instance: Log = {
        let log = Log(env: DDTestMonitor.envReader)
        log.boostrap(config: DDTestMonitor.config)
        return log
    }()
    
    func boostrap(config: Config) {
        isDebug = config.extraDebug
        isDebugTracerCallStack = config.extraDebugCallStack
    }

    static func debug(_ wrapped: @autoclosure () -> String) {
        instance.debug(wrapped())
    }

    static func print(_ message: String) {
        instance.print(message)
    }

    static func measure<T>(name: String, _ operation: () throws -> T) rethrows -> T {
        try instance.measure(name: name, operation)
    }
    
    static func runOnDebug(_ function: @autoclosure () -> Void) {
        if instance.isDebug { function() }
    }
}
