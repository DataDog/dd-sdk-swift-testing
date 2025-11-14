//
//  BreakableResult.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 13/11/2025.
//

internal import EventsExporter

protocol BreakableProtocol: Error {
    associatedtype Return
    associatedtype Failure: Error
    
    var asBreakable: Breakable<Return, Failure> { get }
}

enum Breakable<Return, Failure: Error>: BreakableProtocol {
    case `break`(Return)
    case failure(Failure)
    
    @inlinable
    var asBreakable: Breakable<Return, Failure> { self }
}

typealias BreakableResult<Return, Success, Failure: Error> = Result<Success, Breakable<Return, Failure>>
typealias AsyncBreakableResult<Return, Success, Failure: Error> = AsyncResult<Success, Breakable<Return, Failure>>

extension Result {
    func breakable<Return>(_ return: Return.Type) -> BreakableResult<Return, Success, Failure> {
        mapError { .failure($0) }
    }
}

extension AsyncResult {
    func breakable<Return>(_ return: Return.Type) -> AsyncBreakableResult<Return, V, E> {
        mapError { .failure($0) }
    }
}

extension Result where Failure: BreakableProtocol {
    static func `break`(_ returnValue: Failure.Return) -> BreakableResult<Failure.Return, Success, Failure.Failure> {
        .failure(.break(returnValue))
    }
    
    func breakFlatMap<NewSuccess>(
        _ transform: (Success) -> Result<NewSuccess, Failure.Failure>
    ) -> BreakableResult<Failure.Return, NewSuccess, Failure.Failure> {
        switch self {
        case .failure(let breakable): return .failure(breakable.asBreakable)
        case .success(let val): return transform(val).mapError { .failure($0) }
        }
    }
    
    func breakFlatMapError<NewFailure: Error>(
        _ transform: (Failure.Failure) -> Result<Success, NewFailure>
    ) -> BreakableResult<Failure.Return, Success, NewFailure> {
        flatMapError {
            switch $0.asBreakable {
            case .break(let val): return .failure(.break(val))
            case .failure(let err): return transform(err).mapError { .failure($0) }
            }
        }
    }
    
    func breakMapError<NewFailure: Error>(
        _ transform: (Failure.Failure) -> NewFailure
    ) -> BreakableResult<Failure.Return, Success, NewFailure> {
        mapError {
            switch $0.asBreakable {
            case .break(let val): return .break(val)
            case .failure(let err): return .failure(transform(err))
            }
        }
    }
    
    func breakMapReturn<NewReturn>(
        _ transform: (Failure.Return) -> NewReturn
    ) -> BreakableResult<NewReturn, Success, Failure.Failure> {
        mapError {
            switch $0.asBreakable {
            case .break(let val): return .break(transform(val))
            case .failure(let err): return .failure(err)
            }
        }
    }
    
    func breakResult() -> Result<Success, Failure.Failure> where Success == Failure.Return {
        switch self {
        case .success(let val): return .success(val)
        case .failure(let breakable):
            switch breakable.asBreakable {
            case .break(let val): return .success(val)
            case .failure(let err): return .failure(err)
            }
        }
    }
}

extension AsyncResult where E: BreakableProtocol {
    static func `break`(_ returnValue: E.Return) -> AsyncBreakableResult<E.Return, V, E.Failure> {
        .error(.break(returnValue))
    }
    
    func breakFlatMapResult<NewSuccess, NewFailure: Error>(
        _ transform: @escaping (Result<V, E.Failure>) -> AsyncResult<NewSuccess, NewFailure>
    ) -> AsyncBreakableResult<E.Return, NewSuccess, NewFailure> {
        flatMapResult {
            switch $0 {
            case .failure(let breakable):
                switch breakable.asBreakable {
                case .break(let val): return .error(.break(val))
                case .failure(let err): return transform(.failure(err)).mapError { .failure($0) }
                }
            case .success(let v): return transform(.success(v)).mapError { .failure($0) }
            }
        }
    }
    
    func breakFlatMap<NewSuccess>(
        _ transform: @escaping (V) -> AsyncResult<NewSuccess, E.Failure>
    ) -> AsyncBreakableResult<E.Return, NewSuccess, E.Failure> {
        breakFlatMapResult {
            switch $0 {
            case .success(let v): return transform(v)
            case .failure(let err): return .error(err)
            }
        }
    }
    
    func breakFlatMapError<NewFailure: Error>(
        _ transform: @escaping (E.Failure) -> AsyncResult<V, NewFailure>
    ) -> AsyncBreakableResult<E.Return, V, NewFailure> {
        breakFlatMapResult {
            switch $0 {
            case .success(let v): return .value(v)
            case .failure(let err): return transform(err)
            }
        }
    }
    
    func breakMapResult<V2, E2: Error>(
        _ transform: @escaping (Result<V, E.Failure>) -> Result<V2, E2>
    ) -> AsyncBreakableResult<E.Return, V2, E2> {
        breakFlatMapResult { .init(result: transform($0)) }
    }
    
    func breakMapError<E2>(_ transform: @escaping (E.Failure) -> E2) -> AsyncBreakableResult<E.Return, V, E2> {
        breakMapResult { $0.mapError(transform) }
    }
    
    func breakMapReturn<NewReturn>(
        _ transform: @escaping (E.Return) -> NewReturn
    ) -> AsyncBreakableResult<NewReturn, V, E.Failure> {
        mapError {
            switch $0.asBreakable {
            case .break(let val): return .break(transform(val))
            case .failure(let err): return .failure(err)
            }
        }
    }
    
    func breakResult() -> AsyncResult<V, E.Failure> where V == E.Return {
        mapResult {
            switch $0 {
            case .success(let val): return .success(val)
            case .failure(let breakable):
                switch breakable.asBreakable {
                case .break(let val): return .success(val)
                case .failure(let err): return .failure(err)
                }
            }
        }
    }
}
