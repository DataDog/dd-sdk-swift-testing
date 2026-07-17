/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal protocol HTTPClientType: AnyObject, Sendable {
    /// Send the request and return the response (no body). `observer`, when
    /// provided, is notified once with the request's transport facts.
    @discardableResult
    func send(request: URLRequest, observer: RequestObserver?) async throws(HTTPClient.RequestError) -> HTTPClient.Response
    
    /// Synchronously send `request`, blocking the calling thread until the
    /// response (or a transport error) arrives, or until `timeout` elapses.
    @discardableResult
    func send(request: URLRequest, observer: RequestObserver?) throws(HTTPClient.RequestError) -> HTTPClient.Response
}

extension HTTPClientType {
    /// Send the request and return the response (no body).
    @discardableResult
    func send(request: URLRequest) async throws(HTTPClient.RequestError) -> HTTPClient.Response {
        try await send(request: request, observer: nil)
    }
    
    /// Synchronously send `request`, blocking the calling thread until the response (or a transport error) arrives.
    @discardableResult
    func send(request: URLRequest) throws(HTTPClient.RequestError) -> HTTPClient.Response {
        try send(request: request, observer: nil)
    }
}

/// Client for sending requests over HTTP.
public final class HTTPClient: HTTPClientType {
    private let session: URLSession
    private let debug: Bool
    
    public typealias Response = (response: HTTPURLResponse, data: Data?)

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
        // Fail requests instead of waiting
        configuration.waitsForConnectivity = false
        // TODO: RUMM-123 Optimize `URLSessionConfiguration` for good traffic performance
        // and move session configuration constants to `PerformancePreset`.
        self.init(session: URLSession(configuration: configuration), debug: debug)
    }

    public init(session: URLSession, debug: Bool) {
        self.session = session
        self.debug = debug
    }
    
    @discardableResult
    func send(request: URLRequest, observer: RequestObserver?) async throws(RequestError) -> Response {
        let (result, facts): (Result<Response, RequestError>, ObserverFacts?) = await withUnsafeContinuation { continuation in
            let _ = self._send(request: request, collectFacts: observer != nil) {
                continuation.resume(returning: $0)
            }
        }
        // `RequestObserver` is async: invoke it here, in our own async context,
        // after the (non-async) completion handler has returned.
        if let observer, let facts {
            await observer.requestFinished(durationMs: facts.durationMs,
                                           requestBytes: facts.requestBytes,
                                           responseBytes: facts.responseBytes,
                                           statusCode: facts.statusCode,
                                           transportError: facts.transportError,
                                           failed: facts.failed)
        }
        return try result.get()
    }

    @discardableResult
    func send(request: URLRequest, observer: RequestObserver?) throws(RequestError) -> Response {
        let sema = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var outcome: (Result<Response, RequestError>, ObserverFacts?) = (.failure(.inconsistentSession), nil)
        let task = _send(request: request, collectFacts: observer != nil) { result in
            outcome = result
            sema.signal()
        }
        guard sema.wait(timeout: .now() + request.timeoutInterval) == .success else {
            task.cancel()
            throw .transport(URLError(.timedOut))
        }
        // This synchronous path runs on the teardown/flush path, where we must not
        // block on — or depend on — the cooperative executor. `RequestObserver` is
        // async, so report it fire-and-forget: it records during normal operation
        // and is simply skipped if the executor is no longer scheduled at process
        // exit. Telemetry never delays teardown.
        if let observer, let facts = outcome.1 {
            Task {
                await observer.requestFinished(durationMs: facts.durationMs,
                                               requestBytes: facts.requestBytes,
                                               responseBytes: facts.responseBytes,
                                               statusCode: facts.statusCode,
                                               transportError: facts.transportError,
                                               failed: facts.failed)
            }
        }
        return try outcome.0.get()
    }

    /// The facts a `RequestObserver` needs, captured inside the (non-async)
    /// `URLSessionDataTask` completion handler so the (async) observer can be
    /// invoked afterwards, outside that closure.
    ///
    /// `@unchecked Sendable`: an immutable snapshot whose only non-`Sendable`
    /// member (`transportError`) is read-only, so it is safe to hand to the
    /// observer across a concurrency boundary.
    private struct ObserverFacts: @unchecked Sendable {
        let durationMs: Double
        let requestBytes: Int
        let responseBytes: Int
        let statusCode: Int?
        let transportError: (any Error)?
        let failed: Bool
    }

    private func _send(request: URLRequest,
                       collectFacts: Bool,
                       result: @escaping @Sendable ((Result<Response, RequestError>, ObserverFacts?)) -> Void) -> URLSessionTask
    {
        // Capture the serialized payload size before `deflate` so it reflects
        // the logical request size rather than the compressed wire size.
        let requestBytes = request.httpBody?.count ?? 0
        // Capture only the parts the debug log needs (url, headers, uncompressed
        // body) up front, so the completion handler doesn't retain the whole
        // `URLRequest` — and so the body is shown readable, not deflated.
        let logFields: LogFields? = debug
            ? LogFields(url: request.url!, headers: request.allHTTPHeaderFields, body: request.httpBody)
            : nil
        if let url = logFields?.url {
            Log.debug("Sending request to \(url).....")
        }
        let request = _deflate(request)
        let start = collectFacts ? DispatchTime.now() : nil
        let task = session.dataTask(with: request) { data, response, error in
            // Log request and response
            self._log(request: logFields, response: (data, response, error))
            var facts: ObserverFacts? = nil
            if let start {
                let durationMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                let success = error == nil && (statusCode.map { (200 ..< 400).contains($0) } ?? false)
                facts = ObserverFacts(durationMs: durationMs,
                                      requestBytes: requestBytes,
                                      responseBytes: data?.count ?? 0,
                                      statusCode: statusCode,
                                      transportError: statusCode == nil ? error : nil,
                                      failed: !success)
            }
            result((.init(data: data, response: response, error: error), facts))
        }
        task.resume()
        return task
    }

    private func _deflate(_ request: URLRequest) -> URLRequest {
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

    /// The pieces of a request the debug log needs, captured before `deflate` so
    /// they reflect the logical (uncompressed) request and we don't retain the
    /// whole `URLRequest` for the request's duration.
    private struct LogFields: Sendable {
        let url: URL
        let headers: [String: String]?
        let body: Data?
    }

    private func _log(request: LogFields?, response: (Data?, URLResponse?, Error?)) {
        guard let request else { return }
        let (data, urlres, error) = response
        let httpres = urlres as? HTTPURLResponse
        Log.debug("""
                  [NETWORK REQUEST DEBUG INFO]
                  REQUEST: \(request.url.absoluteString)
                  REQ HEADERS: \(Self._printable(headers: request.headers))
                  REQ BODY: \(Self._printable(request.body))
                  RESPONSE: \(httpres.map { String($0.statusCode) } ?? urlres?.debugDescription ?? "nil")
                  RES HEADERS: \(Self._printable(headers: httpres?.allHeaderFields))
                  RES ERROR: \(error?.localizedDescription ?? "nil")
                  RES DATA: \(Self._printable(data))
                  """)
    }

    /// Render a payload for debug logging: UTF-8 text when decodable (JSON in
    /// nearly all cases), a `<binary N bytes>` marker otherwise, `nil` when absent.
    private static func _printable(_ data: Data?) -> String {
        guard let data else { return "nil" }
        return String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
    }

    /// Header names whose values are credentials and must never be logged.
    /// `HTTPHeader.Field` lowercases its `rawValue`, so compare lowercased.
    private static let _redactedHeaders: Set<String> = [
        HTTPHeader.Field.apiKeyHeaderField.rawValue,
        HTTPHeader.Field.applicationKeyHeaderField.rawValue,
    ]

    /// Render a header set as sorted `key: value` lines, with credential values
    /// (API / application key) replaced by `****`. `nil` when absent/empty.
    private static func _printable<K, V>(headers: [K: V]?) -> String {
        guard let headers, !headers.isEmpty else { return "nil" }
        return "\n\t" + headers.map { key, value in
            let name = "\(key)"
            let shown = _redactedHeaders.contains(name.lowercased()) ? "****" : "\(value)"
            return "\(name): \(shown)"
        }.sorted().joined(separator: "\n\t")
    }
}

extension Result where Success == HTTPClient.Response, Failure == HTTPClient.RequestError {
    init(data: Data?, response: URLResponse?, error: Error?) {
        if let error = error {
            self = .failure(.transport(error))
            return
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            self = .failure(.inconsistentSession)
            return
        }
        if let httpError = HTTPClient.RequestError(response: httpResponse, body: data) {
            self = .failure(httpError)
            return
        }
        self = .success((httpResponse, data))
    }
}
