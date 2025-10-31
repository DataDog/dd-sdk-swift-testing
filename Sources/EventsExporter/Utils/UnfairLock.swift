//
//  UnfairLock.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 30/10/2025.
//

import Foundation

public final class UnfairLock {
    private let _lock: os_unfair_lock_t
    
    public init() {
        _lock = .allocate(capacity: 1)
        _lock.initialize(to: .init())
    }
    
    deinit {
        _lock.deinitialize(count: 1)
        _lock.deallocate()
    }
    
    public func lock() {
        os_unfair_lock_lock(_lock)
    }
    
    public func unlock() {
        os_unfair_lock_unlock(_lock)
    }
    
    public func whileLocked<T>(_ action: () throws -> T) rethrows -> T {
        os_unfair_lock_lock(_lock)
        defer { os_unfair_lock_unlock(_lock) }
        return try action()
    }
}
