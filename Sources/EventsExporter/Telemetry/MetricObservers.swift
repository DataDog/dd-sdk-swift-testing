/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// Hooks that let a higher layer (the SDK's telemetry manager) observe the
/// network/storage internals of `EventsExporter` without this module knowing
/// anything about telemetry metrics. EventsExporter only reports neutral facts
/// (durations, byte sizes, status codes, counts); the consumer decides which
/// metric/tags they map to.
///
/// All hooks are optional and default to `nil` at every injection point, so the
/// exporter behaves identically when no observer is attached.

/// Observes a single HTTP request/response exchange. Reported once per request
/// from the shared `HTTPClient`, so the measurement (timing, payload sizes,
/// status) lives in one place and callers only supply identity/tags.
///
/// `requestBytes` is the size of the serialized request payload that was sent
/// (some metrics, e.g. `endpoint_payload.bytes` / `git_requests.objects_pack_bytes`,
/// track the request size); `responseBytes` is the size of the received body.
/// `statusCode` is `nil` for transport-level failures (no HTTP response);
/// `transportError` carries the raw `URLError` in those cases (e.g. `.timedOut`,
/// `.notConnectedToInternet`) and is `nil` when an HTTP response was received.
/// `failed` is `true` whenever the request did not complete successfully.
public protocol RequestObserver: Sendable {
    func requestFinished(durationMs: Double, requestBytes: Int, responseBytes: Int,
                         statusCode: Int?, transportError: (any Error)?, failed: Bool) async
}

/// Observes a sequence of paginated requests (e.g. Known Tests). Conforms to
/// `RequestObserver` so the same instance can be handed to each per-page HTTP
/// call: it forwards every call unchanged to the wrapped observer while
/// summing the `durationMs` of every call (successful or not — retries still
/// cost wall-clock time) and counting only the succeeded pages, so the caller
/// never times a page itself. Call `finished(totalFetchMs:)` once, after the
/// last page, to report the pagination-level aggregate.
public actor PagedRequestObserver: RequestObserver {
    private let wrapped: RequestObserver?
    private let onPagesFetched: (@Sendable (_ count: Int, _ totalFetchMs: Double, _ totalRequestMs: Double) async -> Void)?
    private var pageCount = 0
    private var totalRequestMs: Double = 0

    public init(wrapping observer: RequestObserver? = nil,
               onPagesFetched: (@Sendable (_ count: Int, _ totalFetchMs: Double, _ totalRequestMs: Double) async -> Void)? = nil) {
        self.wrapped = observer
        self.onPagesFetched = onPagesFetched
    }

    public func requestFinished(durationMs: Double, requestBytes: Int, responseBytes: Int,
                                statusCode: Int?, transportError: (any Error)?, failed: Bool) async {
        totalRequestMs += durationMs
        if !failed { pageCount += 1 }
        await wrapped?.requestFinished(durationMs: durationMs, requestBytes: requestBytes,
                                       responseBytes: responseBytes, statusCode: statusCode,
                                       transportError: transportError, failed: failed)
    }

    /// Reports the pagination-level aggregate; call once after the last page.
    /// `totalFetchMs` is the wall-clock time from the first page request to
    /// the last, supplied by the caller since only it spans the whole loop.
    public func finished(totalFetchMs: Double) async {
        await onPagesFetched?(pageCount, totalFetchMs, totalRequestMs)
    }
}

/// Observes the background upload pipeline that drains stored batches to the
/// intake (one observer per feature store, e.g. spans vs coverage).
///
/// This reports what the worker uniquely knows about a stored batch's lifecycle
/// — the transport-level facts (status code, response size) come from
/// `RequestObserver` on the underlying upload request. `uploadAttempt` is
/// reported once per attempt with the batch size, elapsed time and outcome
/// (`success` = delivered & removed, `retriable` = will be retried);
/// `uploadDropped` once when a batch is abandoned without being delivered.
public protocol UploadObserver: Sendable {
    func uploadAttempt(payloadBytes: Int, durationMs: Double, success: Bool, retriable: Bool)
    func uploadDropped(payloadBytes: Int)
}

/// Observes payload serialization at the storage layer (one observer per feature
/// store). `eventEnqueued` is reported once per event as it is encoded and sent
/// for writing (the source for `events_enqueued_for_serialization`).
/// `payloadFinalized` is reported once when a file is closed/rolled, carrying
/// the number of events in that payload (`events_count`) and the summed time
/// spent serializing them (`events_serialization_ms`).
public protocol PayloadObserver: Sendable {
    func eventEnqueued()
    func payloadFinalized(eventCount: Int, serializationMs: Double)
}

/// Telemetry observers handed to the `Exporter`, grouped per upload feature.
/// Only the features that map to an `endpoint_payload` namespace (spans →
/// `test_cycle`, coverage → `code_coverage`) are represented; everything
/// defaults to `nil`, leaving the pipeline uninstrumented.
public struct ExporterObservers: Sendable {
    public struct Feature: Sendable {
        /// Observes the upload HTTP request itself (size sent, duration, status)
        /// — the source for `endpoint_payload.requests/_ms/bytes/_errors`.
        public let request: RequestObserver?
        /// Observes the background batch lifecycle (attempt outcome, drops).
        public let upload: UploadObserver?
        /// Observes payload serialization (`events_count` / `events_serialization_ms`).
        public let payload: PayloadObserver?

        public init(request: RequestObserver? = nil,
                    upload: UploadObserver? = nil,
                    payload: PayloadObserver? = nil) {
            self.request = request
            self.upload = upload
            self.payload = payload
        }
    }

    public let spans: Feature
    public let coverage: Feature

    public init(spans: Feature = .init(), coverage: Feature = .init()) {
        self.spans = spans
        self.coverage = coverage
    }
}
