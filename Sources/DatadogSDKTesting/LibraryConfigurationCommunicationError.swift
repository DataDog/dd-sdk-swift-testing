/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

/// Thrown by feature factories when fetching library configuration data
/// (`tracerSettings`, `skippableTests`, `knownTests`, `testManagementTests`)
/// or running the git-upload pair (`searchCommits`, `uploadPackFiles`)
/// surfaces a backend communication failure to the caller. Carries enough
/// context (request name, payload, and the failure reason) for the caller to
/// log a meaningful diagnostic. `.unauthorized` and `.communicationFailed`
/// count as communication failures with the backend; the other reasons
/// surface payload encoding or response decoding issues.
struct LibraryConfigurationCommunicationError: Error, CustomStringConvertible {
    enum Reason {
        /// The request payload could not be encoded as JSON.
        case payloadEncodingFailed
        /// The backend rejected the request with HTTP 401 or 403, usually
        /// meaning that DD_API_KEY is missing or incorrect.
        case unauthorized
        /// The backend could not be reached: transport error, non-2xx HTTP
        /// status, or an inconsistent URLSession response. The underlying
        /// upload error is included.
        case communicationFailed(any Error)
        /// The backend responded but the body could not be decoded into the
        /// expected shape. The raw response body and the decoding error are
        /// both included.
        case responseDecodingFailed(body: Data, error: any Error)
    }

    let requestName: String
    let payload: String
    let reason: Reason

    init(requestName: String, payload: String, reason: Reason) {
        self.requestName = requestName
        self.payload = payload
        self.reason = reason
    }

    var description: String {
        var lines: [String]
        switch reason {
        case .payloadEncodingFailed:
            lines = ["\(requestName): request payload could not be encoded"]
        case .unauthorized:
            lines = ["\(requestName): Datadog backend rejected the request as unauthorized. " +
                     "Please verify that DD_API_KEY is correct."]
        case .communicationFailed(let error):
            lines = ["\(requestName): no response from backend: \(error)"]
        case .responseDecodingFailed(let body, let error):
            lines = ["\(requestName): invalid response body: \(error)",
                     "Response: \(String(decoding: body, as: UTF8.self))"]
        }
        lines.append("Payload: \(payload)")
        return lines.joined(separator: "\n")
    }

    /// Translate an `APICallError` from the API wrappers into the
    /// configuration-error shape. The request payload, when not
    /// captured by the caller, is rendered as a best-effort summary.
    init(requestName: String, payload: String, error: APICallError) {
        let reason: Reason
        switch error {
        case .httpError(code: 401, headers: _, body: _),
             .httpError(code: 403, headers: _, body: _):
            reason = .unauthorized
        case .httpError, .transport:
            reason = .communicationFailed(error)
        case .encoding:
            reason = .payloadEncodingFailed
        case .decoding(let body, let decodingError):
            reason = .responseDecodingFailed(body: body, error: decodingError)
        case .idMismatch, .typeMismatch:
            reason = .communicationFailed(error)
        case .fileSystem(let underlying), .unknownError(let underlying):
            reason = .communicationFailed(underlying)
        }
        self.init(requestName: requestName, payload: payload, reason: reason)
    }
}
