/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

final class UnfairLock: Sendable {
    nonisolated(unsafe) private let _lock: os_unfair_lock_t
    
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

final class Synced<V>: Sendable {
    nonisolated(unsafe) private var _value: V
    private let lock = UnfairLock()
    
    init(_ value: V) {
        _value = value
    }
    
    var value: V { lock.whileLocked { _value } }
    
    func use<R>(_ action: (V) throws -> R) rethrows -> R {
        try lock.whileLocked { try action(_value) }
    }
    
    func update<R>(_ action: (inout V) throws -> R) rethrows -> R {
        try lock.whileLocked { try action(&_value) }
    }
}

struct LazySynced<V>: Sendable {
    private enum State {
        case constructor(() throws -> V)
        case value(V)
        case error(any Error)
        
        mutating func get() throws -> V {
            switch self {
            case .value(let v): return v
            case .error(let e): throw e
            case .constructor(let c):
                do {
                    let value = try c()
                    self = .value(value)
                    return value
                } catch {
                    self = .error(error)
                    throw error
                }
            }
        }
    }
    
    private let state: Synced<State>
    
    init(_ constructor: @escaping () throws -> V) {
        state = .init(.constructor(constructor))
    }
    
    func value() throws -> V {
        try state.update { try $0.get() }
    }
    
    func use<R>(_ action: (V) throws -> R) throws -> R {
        try state.update { try action($0.get()) }
    }
    
    func update<R>(_ action: (inout V) throws -> R) throws -> R {
        try state.update { state in
            var value = try state.get()
            let result = try action(&value)
            state = .value(value)
            return result
        }
    }
}
