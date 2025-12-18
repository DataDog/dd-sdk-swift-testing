/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// A type that performs data uploads.
internal protocol DataUploaderType {
    func upload(data: Data) -> AsyncResult<DataUploadStatus, Never>
}

/// Uploads data to server using  provided closure as uploader.
internal struct ClosureDataUploader: DataUploaderType {
    typealias UploadCallback = (Data) -> AsyncResult<Void, HTTPClient.RequestError>
    
    private let _upload: UploadCallback
    
    init(upload: @escaping UploadCallback) {
        self._upload = upload
    }
    
    func upload(data: Data) -> AsyncResult<DataUploadStatus, Never> {
        _upload(data)
            .map { .success }
            .flatMapError { error in
                switch error {
                case .transport, .inconsistentResponse:
                    return .value(.retry)
                case .http(code: let code, headers: let headers, body: _):
                    return .value(.init(httpCode: code, headers: headers))
                }
            }
    }
}

extension Result {
    var error: Failure? {
        switch self {
        case .success(_): return nil
        case .failure(let err): return err
        }
    }
}
