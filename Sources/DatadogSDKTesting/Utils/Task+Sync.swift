/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

func waitForAsync<V, E>(_ function: @Sendable @escaping () async throws(E) -> V) throws(E) -> V {
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
