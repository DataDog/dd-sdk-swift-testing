/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

private final class RunLoopWaiter: @unchecked Sendable {
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

func waitForAsync<V, E>(_ function: @Sendable @escaping () async throws(E) -> V) throws(E) -> V {
    let waiter = RunLoopWaiter()
    var result: Result<V, E>! = nil
    Task<Void, Never> {
        do {
            result = .success(try await function())
        } catch {
            result = .failure(error as! E)
        }
        waiter.signal()
    }
    waiter.wait()
    return try result!.get()
}
