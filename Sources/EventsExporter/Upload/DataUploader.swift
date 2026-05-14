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

/// Synchronously uploads data to server using `HTTPClient`.
internal final class DataUploader: DataUploaderType {
    /// An unreachable upload status - only meant to satisfy the compiler.
    private static let unreachableUploadStatus = DataUploadStatus(needsRetry: false)

    private let httpClient: any HTTPClientType
    private let requestBuilder: RequestBuilder

    init(httpClient: any HTTPClientType, requestBuilder: RequestBuilder) {
        self.httpClient = httpClient
        self.requestBuilder = requestBuilder
    }

    /// Uploads data synchronously (will block current thread) and returns the upload status.
    /// Uses timeout configured for `HTTPClient`.
    ///
    /// Uses `RunLoopWaiter` rather than a bare `DispatchSemaphore`: on the main thread we
    /// spin the run loop instead of blocking it, which is required on watchOS where the
    /// URL-loading machinery (and `URLProtocol`-based test mocks) is dispatched on the
    /// caller's run loop.
    func upload(data: Data) -> DataUploadStatus {
        let request = createRequest(with: data)
        var uploadStatus: DataUploadStatus?

        let waiter = RunLoopWaiter()

        httpClient.send(request: request) { result in
            switch result {
            case .success(let httpResponse):
                uploadStatus = DataUploadStatus(httpResponse: httpResponse)
            case .failure(let error):
                uploadStatus = DataUploadStatus(networkError: error)
            }

            waiter.signal()
        }

        waiter.wait()

        return uploadStatus ?? DataUploader.unreachableUploadStatus
    }

    /// Uploads data synchronously (will block current thread) and returns the response data
    /// Uses timeout configured for `HTTPClient`.
    func uploadWithResponse(data: Data) -> Data? {
        try? uploadWithResult(data: data).get()
    }

    /// Uploads data synchronously and returns the response data on success
    /// or the underlying transport/HTTP error so callers can distinguish a
    /// communication failure from an empty/invalid response.
    func uploadWithResult(data: Data) -> Result<Data, HTTPClient.RequestError> {
        let request = createRequest(with: data)
        var result: Result<Data, HTTPClient.RequestError>?

        let waiter = RunLoopWaiter()

        httpClient.sendWithResult(request: request) { httpResult in
            result = httpResult
            waiter.signal()
        }

        waiter.wait()

        return result ?? .failure(.inconsistentSession)
    }

    private func createRequest(with data: Data) -> URLRequest {
        return requestBuilder.uploadRequest(with: data)
    }
}
