/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// A type that performs data uploads.
internal protocol DataUploaderType {
    /// Asynchronously upload `data`
    /// `timeout` seconds elapse (a per-attempt wall-clock bound).
    func upload(data: Data, timeout: TimeInterval?) async -> DataUploadStatus
    
    /// Synchronously upload `data`, blocking the caller until it finishes or
    /// `timeout` seconds elapse (a per-attempt wall-clock bound).
    func upload(data: Data, timeout: TimeInterval?) -> DataUploadStatus
}

/// Uploads data to the server via a *synchronous* closure (a call to one of the
/// typed API services' synchronous upload methods in `EventsExporter/API/`).
/// The closure throws `APICallError`; the result is mapped to a `DataUploadStatus`.
///
/// The upload is intentionally synchronous and blocks the calling thread. This
/// is what runs on the teardown flush path (from the framework-unload C
/// `destructor` during `exit()`), where the Swift cooperative executor is no
/// longer scheduled — so it must not route through `Task`/`await`/`waitForAsync`
/// (which would suspend and never resume). The underlying synchronous
/// `HTTPClient.send` blocks on a `DispatchSemaphore` signalled directly from
/// `URLSession`'s completion handler, bounded by the request timeout so a
/// stalled intake can't hang teardown.
internal struct ClosureDataUploader: DataUploaderType {
    typealias UploadCallbackSync = (Data, TimeInterval?) throws(APICallError) -> Void
    typealias UploadCallbackAsync = @Sendable (Data, TimeInterval?) async throws(APICallError) -> Void

    private let _sync: UploadCallbackSync
    private let _async: UploadCallbackAsync

    init(sync: @escaping UploadCallbackSync, async: @escaping UploadCallbackAsync) {
        self._sync = sync
        self._async = async
    }
    
    func upload(data: Data, timeout: TimeInterval?) async -> DataUploadStatus {
        do {
            try await _async(data, timeout)
            return .success
        } catch {
            return DataUploadStatus(api: error)
        }
    }

    func upload(data: Data, timeout: TimeInterval?) -> DataUploadStatus {
        do {
            try _sync(data, timeout)
            return .success
        } catch {
            return DataUploadStatus(api: error)
        }
    }
}
