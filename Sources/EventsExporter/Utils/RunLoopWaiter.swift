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
            while _locked { CFRunLoopRunInMode(.defaultMode, 0, true) }
        } else {
            _sema.wait()
            _sema.signal() // So other threads who are waiting can wake up
        }
    }

    public func signal() {
        _locked = false
        _sema.signal()
    }
}
