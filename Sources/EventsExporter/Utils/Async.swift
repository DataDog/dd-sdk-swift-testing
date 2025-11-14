//
//  Async.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 12/11/2025.
//

import Foundation

// This is a simplified implementation of the Future/Promise
// It doesn't support multiple callbacks and could be used only once
// We have to suppport old OS versions so we need it for now
// It will be replaced by async -> Result calls in the future
public final class AsyncResult<V, E: Error> {
    private enum State {
        case initialized
        case value(Result<V, E>)
        case completion((Result<V, E>) -> Void)
        case finalized(Result<V, E>)
    }
    
    private enum Await {
        case value(Result<V, E>)
        case waiter(Waiter<Result<V, E>>)
        
        var value: Result<V, E> {
            switch self {
            case .value(let v): return v
            case .waiter(let w): return w.await()
            }
        }
    }
    
    private var _state: State
    private let _lock: UnfairLock
    
    private var _value: Result<V, E>? {
        switch _state {
        case .value(let value), .finalized(let value): return value
        default: return nil
        }
    }
    
    public var value: Result<V, E>? {
        _lock.whileLocked { _value }
    }
    
    public init(result: Result<V, E>? = nil) {
        self._lock = .init()
        if let res = result {
            self._state = .value(res)
        } else {
            self._state = .initialized
        }
    }
    
    public convenience init(value: V) {
        self.init(result: .success(value))
    }
    
    public convenience init(error: E) {
        self.init(result: .failure(error))
    }
    
    public convenience init(resolver: (_ result: @escaping (Result<V, E>) -> Void) -> Void) {
        self.init()
        resolver { self.complete($0) }
    }
    
    @inlinable
    public static func value(_ value: V) -> AsyncResult<V, E> {
        .init(value: value)
    }
    
    @inlinable
    public static func error(_ error: E) -> AsyncResult<V, E> {
        .init(error: error)
    }
    
    @inlinable
    public static func wrap(resolver: (_ result: @escaping (Result<V, E>) -> Void) -> Void) -> AsyncResult<V, E> {
        .init(resolver: resolver)
    }
    
    public func complete(_ result: Result<V, E>) {
        let cb: ((Result<V, E>) -> Void)? = _lock.whileLocked {
            switch _state {
            case .initialized:
                self._state = .value(result)
                return nil
            case .value(let old):
                assert(false, "Async completed twice. Old \(old), new \(result)")
                return nil
            case .completion(let cb):
                self._state = .finalized(result)
                return cb
            case .finalized(let old):
                assert(false, "Async already finalized. Old \(old), new \(result)")
                return nil
            }
        }
        cb?(result)
    }
    
    public func onComplete(_ callback: @escaping (Result<V, E>) -> Void) {
        let value: Result<V, E>? = _lock.whileLocked { _onComplete(callback) }
        if let value = value {
            callback(value)
        }
    }
    
    // should be called inside lock
    private func _onComplete(_ callback: @escaping (Result<V, E>) -> Void) -> Result<V, E>? {
        switch _state {
        case .initialized:
            self._state = .completion(callback)
            return nil
        case .value(let result):
            self._state = .finalized(result)
            return result
        case .completion(_):
            assert(false, "Complete callback added twice")
            return nil
        case .finalized(let result):
            assert(false, "Async already finalized with \(result)")
            return nil
        }
    }
    
    /// Await for operation to complete. Will block current thread
    public func await() -> Result<V, E> {
        let wait: Await = _lock.whileLocked {
            guard let value = _value else {
                return .waiter(Waiter { let _ = _onComplete($0) })
            }
            return .value(value)
        }
        return wait.value
    }
    
    public var asVoid: AsyncResult<Void, E> {
        map { _ in () }
    }
    
    public func peek(_ peeker: @escaping (Result<V, E>) -> Void) -> AsyncResult<V, E> {
        flatMapResult {
            peeker($0)
            return AsyncResult(result: $0)
        }
    }
    
    public func flatMapResult<V2, E2>(_ transform: @escaping (Result<V, E>) -> AsyncResult<V2, E2>) -> AsyncResult<V2, E2> {
        .wrap { result in
            self.onComplete { transform($0).onComplete { result($0) } }
        }
    }
    
    public func flatMap<V2>(_ transform: @escaping (V) -> AsyncResult<V2, E>) -> AsyncResult<V2, E> {
        flatMapResult {
            switch $0 {
            case .failure(let err): return .error(err)
            case .success(let value): return transform(value)
            }
        }
    }
    
    public func flatMapError<E2>(_ transform: @escaping (E) -> AsyncResult<V, E2>) -> AsyncResult<V, E2> {
        flatMapResult {
            switch $0 {
            case .success(let value): return .value(value)
            case .failure(let err): return transform(err)
            }
        }
    }
    
    public func mapResult<V2, E2>(_ transform: @escaping (Result<V, E>) -> Result<V2, E2>) -> AsyncResult<V2, E2> {
        flatMapResult { .init(result: transform($0)) }
    }
    
    public func map<V2>(_ transform: @escaping (V) -> V2) -> AsyncResult<V2, E> {
        mapResult { $0.map(transform) }
    }
    
    public func mapError<E2>(_ transform: @escaping (E) -> E2) -> AsyncResult<V, E2> {
        mapResult { $0.mapError(transform) }
    }
}

public extension Result {
    var asVoid: Result<Void, Failure> {
        map { _ in () }
    }
    
    func async() -> AsyncResult<Success, Failure> {
        AsyncResult(result: self)
    }
}

public final class Waiter<T> {
    private var _value: T?
    private let _semaphore: DispatchSemaphore
    
    
    public init(_ wrap: (@escaping (T) -> Void) -> Void) {
        self._semaphore = DispatchSemaphore(value: 0)
        wrap { result in
            self._value = result
            self._semaphore.signal()
        }
    }
    
    public func await() -> T {
        self.await(timeout: .distantFuture)!
    }
    
    public func await(timeout: DispatchTime) -> T? {
        let _ = _semaphore.wait(timeout: timeout)
        return _value
    }
}
