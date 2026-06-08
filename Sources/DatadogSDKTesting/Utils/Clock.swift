/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter
#if !os(watchOS)
internal import Kronos
#endif
internal import OpenTelemetrySdk

protocol UnsafeClock: OpenTelemetrySdk.Clock, Sendable, DateProvider {
    func faillableSync() async throws
}

extension UnsafeClock {
    @inlinable
    func currentDate() -> Date { self.now }
}

protocol Clock: UnsafeClock {
    func sync() async
}

extension Clock {
    @inlinable
    func faillableSync() async throws { await sync() }
}

#if !os(watchOS)
final class NTPClock: UnsafeClock {
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
    
    func faillableSync() async throws {
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
#endif

final class DateClock: Clock {
    func sync() async {}
    var now: Date { Date() }
}

/// A clock that wraps an inner clock and falls back to the system wall clock
/// if the inner clock hasn't synced successfully. Captures are always safe:
/// `now` never crashes regardless of sync state, and `sync()` never throws
/// — failures are absorbed internally. This removes the need to replace the
/// clock reference after a failed NTP sync.
final class FallbackClock: Clock, @unchecked Sendable {
    private let clock: Synced<any UnsafeClock>
    private let fallback: @Sendable () -> any Clock

    init(_ unsafe: any UnsafeClock, _ fallback: @escaping @Sendable () -> any Clock) {
        self.clock = .init(unsafe)
        self.fallback = fallback
    }

    func sync() async {
        do {
            try await clock.value.faillableSync()
        } catch {
            clock.update { $0 = self.fallback() }
        }
    }
    
    var now: Date { clock.value.now }
}
