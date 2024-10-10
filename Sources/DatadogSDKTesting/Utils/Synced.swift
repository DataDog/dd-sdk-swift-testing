/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

final class UnfairLock {
    private let _lock: os_unfair_lock_t
    
    init() {
        _lock = .allocate(capacity: 1)
        _lock.initialize(to: .init())
    }
    
    deinit {
        _lock.deinitialize(count: 1)
        _lock.deallocate()
    }
    
    func lock() {
        os_unfair_lock_lock(_lock)
    }
    
    func unlock() {
        os_unfair_lock_unlock(_lock)
    }
    
    func whileLocked<T>(_ action: () throws -> T) rethrows -> T {
        os_unfair_lock_lock(_lock)
        defer { os_unfair_lock_unlock(_lock) }
        return try action()
    }
}

struct Synced<V> {
    private var _value: V
    private let lock = UnfairLock()
    
    init(_ value: V) {
        _value = value
    }
    
    var value: V { lock.whileLocked { _value } }
    
    func use<R>(_ action: (V) throws -> R) rethrows -> R {
        try lock.whileLocked { try action(_value) }
    }
    
    mutating func update<R>(_ action: (inout V) throws -> R) rethrows -> R {
        try lock.whileLocked { try action(&_value) }
    }
}

struct LazySynced<V> {
    private enum State {
        case constructor(() throws -> V)
        case value(V)
        case error(any Error)
    }
    
    private let lock = UnfairLock()
    private var state: State
    
    init(_ constructor: @escaping () throws -> V) {
        state = .constructor(constructor)
    }
    
    mutating func value() throws -> V {
        try lock.whileLocked { try get_unsynced() }
    }
    
    mutating func use<R>(_ action: (V) throws -> R) throws -> R {
        try lock.whileLocked { try action(get_unsynced()) }
    }
    
    mutating func update<R>(_ action: (inout V) throws -> R) throws -> R {
        try lock.whileLocked {
            var value = try get_unsynced()
            let result = try action(&value)
            state = .value(value)
            return result
        }
    }
    
    private mutating func get_unsynced() throws -> V {
        switch state {
        case .value(let v): return v
        case .error(let e): throw e
        case .constructor(let c):
            do {
                let value = try c()
                state = .value(value)
                return value
            } catch {
                state = .error(error)
                throw error
            }
        }
    }
}

extension Synced where V: FixedWidthInteger {
    mutating func checkedAdd(_ right: V, max: V = .max, min: V = .min) -> V? {
        update { lft in
            let (sum, overflow) = lft.addingReportingOverflow(right)
            guard !overflow, sum <= max, sum >= min else { return nil }
            lft = sum
            return sum
        }
    }
}
