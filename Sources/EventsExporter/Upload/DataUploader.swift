/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// A type that performs data uploads.
internal protocol DataUploaderType {
    func upload(data: Data) -> DataUploadStatus
}

/// Uploads data to the server via an async closure (typically a call to one of
/// the typed API services in `EventsExporter/API/`). The closure throws
/// `HTTPClient.RequestError`; the result is mapped to a `DataUploadStatus`.
internal struct ClosureDataUploader: DataUploaderType {
    typealias UploadCallback = @Sendable (Data) async throws(APICallError) -> Void

    private let _upload: UploadCallback

    init(upload: @escaping UploadCallback) {
        self._upload = upload
    }

    func upload(data: Data) -> DataUploadStatus {
        let upload = self._upload
        do {
            try waitForAsync { () async throws(APICallError) -> Void in
                try await upload(data)
            }
            return .success
        } catch {
            return DataUploadStatus(api: error)
        }
    }
}
