/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

// MARK: - Adapters bridging EventsExporter observers to the telemetry metrics

/// These adapters conform to the neutral observer protocols `EventsExporter`
/// reports through (`RequestObserver` / `UploadObserver` / `PayloadObserver`)
/// and forward the facts to caller-supplied closures. The call site (which
/// knows the metric family and tags) wires the closures to the relevant
/// `Telemetry.metrics.*` instruments; the common `statusCode → ErrorType`
/// mapping lives here so every call site agrees on it.
extension Telemetry {
    /// Maps an HTTP status code (or its absence) to the telemetry `error_type`.
    /// When `statusCode` is `nil` (transport failure), checks `transportError`:
    /// a `URLError.timedOut` maps to `.timeout`; everything else maps to `.network`.
    static func errorType(statusCode: Int?, transportError: (any Error)? = nil) -> ErrorType {
        guard let code = statusCode else {
            if (transportError as? URLError)?.code == .timedOut { return .timeout }
            return .network
        }
        switch code {
        case 400 ..< 500: return .statusCode4xx
        case 500 ..< 600: return .statusCode5xx
        default: return .network
        }
    }

    /// Bridges a single HTTP request's facts to per-family metric closures.
    /// Each closure is optional so a family only wires the metrics it has.
    struct RequestMetricsObserver: RequestObserver {
        /// The request happened (counted regardless of success).
        var onRequest: (@Sendable () async -> Void)? = nil
        /// Request round-trip duration, in milliseconds.
        var onDurationMs: (@Sendable (Double) async -> Void)? = nil
        /// Size of the serialized request payload, in bytes.
        var onRequestBytes: (@Sendable (Int) async -> Void)? = nil
        /// Size of the received response body, in bytes.
        var onResponseBytes: (@Sendable (Int) async -> Void)? = nil
        /// The request failed; the derived `error_type` is supplied.
        var onError: (@Sendable (ErrorType) async -> Void)? = nil

        func requestFinished(durationMs: Double, requestBytes: Int, responseBytes: Int,
                             statusCode: Int?, transportError: (any Error)?, failed: Bool) async {
            await onRequest?()
            await onDurationMs?(durationMs)
            await onRequestBytes?(requestBytes)
            await onResponseBytes?(responseBytes)
            if failed { await onError?(Telemetry.errorType(statusCode: statusCode, transportError: transportError)) }
        }
    }

    /// Bridges the background upload pipeline's batch lifecycle to closures.
    struct UploadMetricsObserver: UploadObserver {
        var onAttempt: (@Sendable (_ payloadBytes: Int, _ durationMs: Double, _ success: Bool, _ retriable: Bool) -> Void)? = nil
        var onDropped: (@Sendable (_ payloadBytes: Int) -> Void)? = nil

        func uploadAttempt(payloadBytes: Int, durationMs: Double, success: Bool, retriable: Bool) {
            onAttempt?(payloadBytes, durationMs, success, retriable)
        }

        func uploadDropped(payloadBytes: Int) {
            onDropped?(payloadBytes)
        }
    }

    /// Bridges payload serialization facts (`events_enqueued_for_serialization`,
    /// `events_count`, `events_serialization_ms`) to closures.
    struct PayloadMetricsObserver: PayloadObserver {
        var onEnqueued: (@Sendable () -> Void)? = nil
        var onFinalized: (@Sendable (_ eventCount: Int, _ serializationMs: Double) -> Void)? = nil

        func eventEnqueued() {
            onEnqueued?()
        }

        func payloadFinalized(eventCount: Int, serializationMs: Double) {
            onFinalized?(eventCount, serializationMs)
        }
    }
}

// MARK: - Per-family request observers

/// Ready-made `RequestObserver`s that map an API request's transport facts to a
/// metric family (`request` / `*_ms` / `*_errors`, plus `response_bytes` /
/// request `bytes` where the family has them). Feature call sites pass these
/// into the API methods. Response item counts (e.g. `response_tests`) come from
/// the parsed result at the call site, not from these observers.
extension Telemetry {
    var gitSettingsRequestObserver: RequestMetricsObserver {
        let m = metrics.gitRequests
        return RequestMetricsObserver(
            onRequest: { m.settings.add() },
            onDurationMs: { m.settingsMs.record($0) },
            onError: { m.settingsErrors.add(errorType: $0) }
        )
    }

    var gitSearchCommitsRequestObserver: RequestMetricsObserver {
        let m = metrics.gitRequests
        return RequestMetricsObserver(
            onRequest: { m.searchCommits.add() },
            onDurationMs: { m.searchCommitsMs.record($0) },
            onError: { m.searchCommitsErrors.add(errorType: $0) }
        )
    }

    var gitObjectsPackRequestObserver: RequestMetricsObserver {
        let m = metrics.gitRequests
        return RequestMetricsObserver(
            onRequest: { m.objectsPack.add() },
            onDurationMs: { m.objectsPackMs.record($0) },
            onRequestBytes: { m.objectsPackBytes.record(Double($0)) },
            onError: { m.objectsPackErrors.add(errorType: $0) }
        )
    }

    var skippableTestsRequestObserver: RequestMetricsObserver {
        let m = metrics.itrSkippableTests
        return RequestMetricsObserver(
            onRequest: { m.request.add() },
            onDurationMs: { m.requestMs.record($0) },
            onResponseBytes: { m.responseBytes.record(Double($0)) },
            onError: { m.requestErrors.add(errorType: $0) }
        )
    }

    var knownTestsRequestObserver: PagedRequestObserver {
        let m = metrics.knownTests
        return PagedRequestObserver(
            wrapping: RequestMetricsObserver(
                onRequest: { m.request.add() },
                onDurationMs: { m.requestMs.record($0) },
                onResponseBytes: { m.responseBytes.record(Double($0)) },
                onError: { m.requestErrors.add(errorType: $0) }
            ),
            onPagesFetched: { count, totalFetchMs, totalRequestMs in
                m.pagesFetched.record(Double(count))
                m.totalFetchMs.record(totalFetchMs)
                m.totalRequestMs.record(totalRequestMs)
            }
        )
    }

    var testManagementRequestObserver: RequestMetricsObserver {
        let m = metrics.testManagementTests
        return RequestMetricsObserver(
            onRequest: { m.request.add() },
            onDurationMs: { m.requestMs.record($0) },
            onResponseBytes: { m.responseBytes.record(Double($0)) },
            onError: { m.requestErrors.add(errorType: $0) }
        )
    }
}
