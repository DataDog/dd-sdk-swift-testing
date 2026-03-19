//
//  Task+Sync.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 19/03/2026.
//

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
    Task<Void, Never>.detached {
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
