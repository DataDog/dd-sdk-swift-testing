/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

private enum HTTPResponseStatusCode: Int {
    /// The request has been accepted for processing.
    case accepted = 202
    /// The server cannot or will not process the request (client error).
    case badRequest = 400
    /// The request lacks valid authentication credentials.
    case unauthorized = 401
    /// The server understood the request but refuses to authorize it.
    case forbidden = 403
    /// The server would like to shut down the connection.
    case requestTimeout = 408
    /// The request entity is larger than limits defined by server.
    case payloadTooLarge = 413
    /// The client has sent too many requests in a given amount of time.
    case tooManyRequests = 429
    /// The server encountered an unexpected condition.
    case internalServerError = 500
    /// The server is not ready to handle the request probably because it is overloaded.
    case serviceUnavailable = 503
    /// An unexpected status code.
    case unexpected = -999

    /// Whether the upload should be retried for this status (e.g. 503 — try again later).
    var needsRetry: Bool {
        switch self {
        case .accepted, .badRequest, .unauthorized, .forbidden, .payloadTooLarge:
            return false
        case .requestTimeout, .tooManyRequests, .internalServerError, .serviceUnavailable:
            return true
        case .unexpected:
            return false
        }
    }
}

/// The status of a single upload attempt.
internal struct DataUploadStatus {
    /// If upload needs to be retried because its associated data was not delivered but it may succeed
    /// in the next attempt (i.e. it failed due to device leaving signal range or a temporary server unavailability).
    /// If `false` then data should be deleted as it does not need any more upload attempts.
    let needsRetry: Bool

    /// Server-supplied retry-after (in seconds) when available.
    let waitTime: TimeInterval?
}

extension DataUploadStatus {
    // MARK: - Initialization

    init(httpResponse: HTTPURLResponse) {
        let statusCode = HTTPResponseStatusCode(rawValue: httpResponse.statusCode) ?? .unexpected
        self.init(needsRetry: statusCode.needsRetry, waitTime: nil)
    }

    init(httpCode: Int, headers: [HTTPHeader.Field: String]) {
        let statusCode = HTTPResponseStatusCode(rawValue: httpCode) ?? .unexpected
        switch statusCode {
        case .tooManyRequests:
            var waitTime: TimeInterval? = nil
            if let retryAfter = headers[.retryAfterHeaderField], let retry = TimeInterval(retryAfter) {
                waitTime = retry
            } else if let rateLimit = headers[.rateLimitResetHeaderField], let retry = TimeInterval(rateLimit) {
                waitTime = retry
            }
            self.init(needsRetry: true, waitTime: waitTime)
        default:
            self.init(needsRetry: statusCode.needsRetry, waitTime: nil)
        }
    }

    init(networkError: HTTPClient.RequestError) {
        switch networkError {
        case .http(code: let code, headers: let headers, body: _):
            self.init(httpCode: code, headers: headers)
        case .transport, .inconsistentSession:
            self.init(needsRetry: true, waitTime: nil)
        }
    }

    static var success: DataUploadStatus { .init(needsRetry: false, waitTime: nil) }
    static var retry: DataUploadStatus { .init(needsRetry: true, waitTime: nil) }
}
