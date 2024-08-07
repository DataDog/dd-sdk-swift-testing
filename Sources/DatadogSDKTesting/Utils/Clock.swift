/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import Kronos
@_implementationOnly import OpenTelemetrySdk

protocol Clock: OpenTelemetrySdk.Clock {
    func sync() throws
}

final class NTPClock: Clock {
    /// List of Datadog NTP pools.
    static let datadogNTPServers = [
        "0.datadog.pool.ntp.org",
        "1.datadog.pool.ntp.org",
        "2.datadog.pool.ntp.org",
        "3.datadog.pool.ntp.org"
    ]
    
    final class RunLoopWaiter {
        private let _sema: DispatchSemaphore = DispatchSemaphore(value: 0)
        private var _locked: Bool = true
        
        func wait() {
            if Thread.isMainThread {
                while _locked { CFRunLoopRunInMode(.defaultMode, 0, true) }
            } else {
                _sema.wait()
                _sema.signal() // So other threads who are waiting can wake up
            }
        }
        
        func signal() {
            _locked = false
            _sema.signal()
        }
    }
    
    enum State {
        case nonsynced
        case synced(() -> Date)
        case syncing(RunLoopWaiter)
        
        func now() throws -> Date {
            switch self {
            case .synced(let f): return f()
            default: throw InternalError(description: "NTPClock is not synced")
            }
        }
    }
    
    private var _state: Synced<State> = Synced(.nonsynced)
    
    func sync() throws {
        _state.update { state -> RunLoopWaiter? in
            switch state {
            case .synced(_): return nil
            case .syncing(let w): return w
            case .nonsynced:
                let waiter = RunLoopWaiter()
                state = .syncing(waiter)
                
                if Thread.isMainThread {
                    self._sync(waiter: waiter)
                } else {
                    DispatchQueue.main.async { self._sync(waiter: waiter) }
                }
                
                return waiter
            }
        }?.wait()
    }
    
    // Should be called on the main thread
    private func _sync(waiter: RunLoopWaiter) {
        Kronos.Clock.sync(
            from: Self.datadogNTPServers.randomElement()!,
            samples: 2, first: nil
        ) { date, _ in
            if date != nil {
                self._state.update { $0 = .synced({ Kronos.Clock.now! }) }
            } else {
                self._state.update { $0 = .synced({ Date() }) }
                Log.print("NTP server sync failed")
            }
            waiter.signal()
        }
    }

    var now: Date { try! _state.value.now() }
}

final class DateClock: Clock {
    func sync() throws {}
    
    var now: Date { Date() }
}
