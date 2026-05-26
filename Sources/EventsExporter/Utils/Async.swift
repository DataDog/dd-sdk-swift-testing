/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// Runs the supplied async work on a detached high-priority Task and blocks
/// the calling thread until the work completes. On the main thread the wait
/// is implemented by spinning the run loop (see `RunLoopWaiter`), which is
/// required on watchOS where the URL-loading machinery is dispatched on the
/// caller's run loop.
public func waitForAsync<V, E: Error>(_ function: @Sendable @escaping () async throws(E) -> V) throws(E) -> V {
    let waiter = RunLoopWaiter()
    var result: Result<V, E>! = nil
    Task<Void, Never>.detached(priority: .high) {
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
