/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// Single-shot waiter that releases when `signal()` is called.
///
/// On the main thread it spins the run loop instead of blocking, which is required on
/// platforms (notably watchOS) where `URLProtocol.startLoading` is dispatched on a
/// queue tied to the caller's run loop. A plain `DispatchSemaphore.wait()` on main
/// stalls the run loop and prevents the URL-loading machinery from making progress.
public final class RunLoopWaiter: @unchecked Sendable {
    private let _sema: DispatchSemaphore
    private var _locked: Bool
    
    public init() {
        self._sema = DispatchSemaphore(value: 0)
        self._locked = true
    }

    public func wait() {
        if Thread.isMainThread {
            // Block in the main run loop until either `signal()` wakes us up via
            // `CFRunLoopWakeUp` (the fast path) or the per-iteration timeout
            // elapses (safety net in case the wake-up event arrives before
            // `CFRunLoopRunInMode` enters its wait state, or in case the run loop
            // has no other sources installed and would otherwise return early).
            while _locked { CFRunLoopRunInMode(.defaultMode, 0.05, true) }
        } else {
            _sema.wait()
            _sema.signal() // So other threads who are waiting can wake up
        }
    }

    public func signal() {
        _locked = false
        _sema.signal()
        // Post a no-op block onto the main run loop and wake it so a `wait()`
        // call spinning there returns from `CFRunLoopRunInMode` immediately and
        // re-evaluates `_locked` instead of waiting out the timeout.
        let main = CFRunLoopGetMain()
        CFRunLoopPerformBlock(main, CFRunLoopMode.commonModes.rawValue) { }
        CFRunLoopWakeUp(main)
    }
}
