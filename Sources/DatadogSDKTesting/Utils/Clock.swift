/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import Kronos
internal import OpenTelemetrySdk

protocol Clock: OpenTelemetrySdk.Clock, Sendable {
    func sync() async throws
}

final class NTPClock: Clock {
    /// List of Datadog NTP pools.
    static let datadogNTPServers = [
        "0.datadog.pool.ntp.org",
        "1.datadog.pool.ntp.org",
        "2.datadog.pool.ntp.org",
        "3.datadog.pool.ntp.org"
    ]
    
    enum State {
        case nonsynced
        case synced(() -> Date)
        case syncing(Task<Void, any Error>)
        case failed
        
        func now() throws -> Date {
            switch self {
            case .synced(let f): return f()
            default: throw InternalError(description: "NTPClock is not synced")
            }
        }
    }
    
    private let _state: Synced<State> = Synced(.nonsynced)
    
    func sync() async throws {
        let task = _state.update { state -> Task<Void, any Error>? in
            switch state {
            case .synced(_): return nil
            case .syncing(let task): return task
            case .nonsynced, .failed:
                let task = Task { @MainActor in
                    try await withUnsafeThrowingContinuation { cont in
                        self._sync(continuation: cont)
                    }
                }
                state = .syncing(task)
                return task
            }
        }
        try await task?.value
    }
    
    // Should be called on the main thread
    private func _sync(continuation: UnsafeContinuation<Void, any Error>) {
        Kronos.Clock.sync(
            from: Self.datadogNTPServers.randomElement()!,
            samples: 2, first: nil
        ) { date, _ in
            if date != nil {
                self._state.update { $0 = .synced({ Kronos.Clock.now! }) }
                continuation.resume()
            } else {
                self._state.update { $0 = .failed }
                continuation.resume(throwing: InternalError(description: "NTP server sync failed"))
            }
        }
    }

    var now: Date { try! _state.value.now() }
}

final class DateClock: Clock {
    func sync() async {}
    
    var now: Date { Date() }
}
