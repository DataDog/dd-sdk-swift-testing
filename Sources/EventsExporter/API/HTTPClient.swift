/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal protocol HTTPClientType: AnyObject, Sendable {
    /// Send the request and return the response (no body). `observer`, when
    /// provided, is notified once with the request's transport facts.
    func send(request: URLRequest, observer: RequestObserver?) async throws(HTTPClient.RequestError) -> HTTPURLResponse
    /// Send the request and return the response body.
    func sendWithResponse(request: URLRequest, observer: RequestObserver?) async throws(HTTPClient.RequestError) -> Data
}

extension HTTPClientType {
    /// Send the request and return the response (no body).
    func send(request: URLRequest) async throws(HTTPClient.RequestError) -> HTTPURLResponse {
        try await send(request: request, observer: nil)
    }

    /// Send the request and return the response body.
    func sendWithResponse(request: URLRequest) async throws(HTTPClient.RequestError) -> Data {
        try await sendWithResponse(request: request, observer: nil)
    }
}

/// Client for sending requests over HTTP.
public final class HTTPClient: HTTPClientType {
    private let session: URLSession
    private let debug: Bool

    public enum RequestError: Error, CustomStringConvertible {
        case http(code: Int, headers: [HTTPHeader.Field: String], body: Data?)
        case transport(any Error)
        /// An error returned if `URLSession` response state is inconsistent (like no data, no response and no error).
        /// The code execution in `URLSessionTransport` should never reach its initialization.
        case inconsistentSession

        public var isUnauthorized: Bool {
            switch self {
            case .http(code: 401, headers: _, body: _),
                 .http(code: 403, headers: _, body: _):
                return true
            default: return false
            }
        }

        public var description: String {
            switch self {
            case .http(let code, _, let body):
                if let body, !body.isEmpty {
                    return "HTTP \(code): \(String(decoding: body, as: UTF8.self))"
                }
                return "HTTP \(code)"
            case .transport(let error):
                return "transport error: \(error.localizedDescription)"
            case .inconsistentSession:
                return "inconsistent URLSession response"
            }
        }

        init?(response: HTTPURLResponse, body: Data?) {
            if (200..<400).contains(response.statusCode) {
                return nil
            }
            let headers: [(HTTPHeader.Field, String)] = response.allHeaderFields.compactMap { key, val in
                guard let key = key as? String else { return nil }
                guard let val = val as? String else { return nil }
                return (.init(key), val)
            }
            self = .http(code: response.statusCode,
                         headers: Dictionary(headers) { "\($0),\($1)" },
                         body: body)
        }
    }

    public convenience init(debug: Bool) {
        let configuration: URLSessionConfiguration = .ephemeral
        // NOTE: RUMM-610 Default behaviour of `.ephemeral` session is to cache requests.
        // To not leak requests memory (including their `.httpBody` which may be significant)
        // we explicitly opt-out from using cache. This cannot be achieved using `.requestCachePolicy`.
        configuration.urlCache = nil
        // TODO: RUMM-123 Optimize `URLSessionConfiguration` for good traffic performance
        // and move session configuration constants to `PerformancePreset`.
        self.init(session: URLSession(configuration: configuration), debug: debug)
    }

    public init(session: URLSession, debug: Bool) {
        self.session = session
        self.debug = debug
    }

    /// Send the request and return the response (no body).
    func send(request: URLRequest, observer: RequestObserver?) async throws(RequestError) -> HTTPURLResponse {
        try await perform(request, observer: observer) { httpClientResult(for: $0) }
    }

    /// Send the request and return the response body.
    func sendWithResponse(request: URLRequest, observer: RequestObserver?) async throws(RequestError) -> Data {
        try await perform(request, observer: observer) { httpClientResultWithData(for: $0) }
    }

    private func perform<T>(
        _ request: URLRequest,
        observer: RequestObserver?,
        _ resultMapping: @escaping (_ taskResult: (Data?, URLResponse?, Error?)) -> Result<T, RequestError>
    ) async throws(RequestError) -> T {
        // Capture the serialized payload size before `deflate` so it reflects
        // the logical request size rather than the compressed wire size.
        let requestBytes = request.httpBody?.count ?? 0
        let request = deflate(request)
        let start = observer != nil ? DispatchTime.now() : nil
        let result: Result<T, RequestError> = await withCheckedContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                self.log(request: request, response: (data, response, error))
                if let observer, let start {
                    let durationMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
                    let statusCode = (response as? HTTPURLResponse)?.statusCode
                    let success = error == nil && (statusCode.map { (200 ..< 400).contains($0) } ?? false)
                    observer.requestFinished(durationMs: durationMs,
                                             requestBytes: requestBytes,
                                             responseBytes: data?.count ?? 0,
                                             statusCode: statusCode,
                                             failed: !success)
                }
                continuation.resume(returning: resultMapping((data, response, error)))
            }
            task.resume()
        }
        return try result.get()
    }
    
    private func deflate(_ request: URLRequest) -> URLRequest {
        if request.value(forHTTPHeader: .contentEncodingHeaderField) == ContentEncoding.deflate.rawValue {
            var request = request
            guard let body = request.httpBody, let deflated = body.deflated else {
                request.setValue(nil, forHTTPHeader: .contentEncodingHeaderField)
                Log.print("HTTP payload compression failed. Sending uncompressed.")
                return request
            }
            request.httpBody = deflated
            return request
        }
        return request
    }

    private func log(request: URLRequest, response: (Data?, URLResponse?, Error?)) {
        guard debug else { return }
        let (data, urlres, error) = response
        guard let httpres = urlres as? HTTPURLResponse else {
            let res = urlres?.description ?? "nil"
            let err = error?.localizedDescription ?? "nil"
            let data = data?.description ?? "nil"
            Log.debug("[NET] => \(request)\n\tERR: \(err)\n\tRES: \(res)\n\tDATA: \(data))")
            return
        }
        Log.debug("""
                  [NET] => \(request.url!)
                  RES CODE: \(httpres.statusCode)
                  ERROR: \(error?.localizedDescription ?? "")
                  DATA: \(data.flatMap{String(data: $0, encoding: .utf8)} ?? "")
                  """)
    }
}

/// An error returned if `URLSession` response state is inconsistent (like no data, no response and no error).
/// The code execution in `URLSessionTransport` should never reach its initialization.
internal struct URLSessionTransportInconsistencyException: Error {}

/// As `URLSession` returns 3-values-tuple for request execution, this function applies consistency constraints and turns
/// it into only two possible states of `HTTPTransportResult`.
private func httpClientResult(for urlSessionTaskCompletion: (Data?, URLResponse?, Error?)) -> Result<HTTPURLResponse, HTTPClient.RequestError> {
    let (data, response, error) = urlSessionTaskCompletion

    if let error = error {
        return .failure(.transport(error))
    }

    guard let httpResponse = response as? HTTPURLResponse else {
        return .failure(.inconsistentSession)
    }

    if let httpError = HTTPClient.RequestError(response: httpResponse, body: data) {
        return .failure(httpError)
    }

    return .success(httpResponse)
}

/// As `URLSession` returns 3-values-tuple for request execution, this function applies consistency constraints and turns
/// it into only two possible states of `HTTPTransportResult`.
private func httpClientResultWithData(for urlSessionTaskCompletion: (Data?, URLResponse?, Error?)) -> Result<Data, HTTPClient.RequestError> {
    let (data, response, error) = urlSessionTaskCompletion

    if let error = error {
        return .failure(.transport(error))
    }

    guard let httpResponse = response as? HTTPURLResponse else {
        return .failure(.inconsistentSession)
    }

    if let httpError = HTTPClient.RequestError(response: httpResponse, body: data) {
        return .failure(httpError)
    }

    return .success(data ?? Data())
}
