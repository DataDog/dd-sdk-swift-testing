/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// Client for sending requests over HTTP.
public final class HTTPClient {
    private let session: URLSession
    private let debug: Bool
    
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
    
    func send(request: URLRequest) -> AsyncResult<HTTPURLResponse, RequestError> {
        .wrap { completion in
            let task = session.dataTask(with: deflate(request)) { data, response, error in
                self.log(request: request, response: (data, response, error))
                completion(httpClientResult(for: (data, response, error)))
            }
            task.resume()
        }
    }
    
    func sendWithResponse(request: URLRequest) -> AsyncResult<Data, RequestError> {
        .wrap { completion in
            let task = session.dataTask(with: deflate(request)) { data, response, error in
                self.log(request: request, response: (data, response, error))
                completion(httpClientResultWithData(for: (data, response, error)))
            }
            task.resume()
        }
    }
    
    private func deflate(_ request: URLRequest) -> URLRequest {
        if request.value(forHTTPHeader: .contentEncodingHeaderField) == ContentEncoding.deflate.rawValue {
            var request = request
            request.httpBody = request.httpBody?.deflated
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
        
    public enum RequestError: Error {
        case http(code: Int, headers: [HTTPHeader.Field: String], body: Data?)
        case inconsistentResponse
        case transport(any Error)
        
        init?(response: HTTPURLResponse, body: Data?) {
            if (200..<300).contains(response.statusCode) {
                return nil
            }
            let headers: [(HTTPHeader.Field, String)] = response.allHeaderFields.compactMap { key, val in
                guard let key = key as? String else { return nil }
                guard let val = val as? String else { return nil }
                return (.init(key.lowercased()), val)
            }
            self = .http(code: response.statusCode,
                         headers: Dictionary(headers) { "\($0),\($1)" },
                         body: body)
        }
    }
}

extension URL {
    func appendingQueryItems(_ queryItems: [URLQueryItem]) -> URL {
        var url = self
        url.appendQueryItems(queryItems)
        return url
    }
    
    mutating func appendQueryItems(_ queryItems: [URLQueryItem]) {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: true)!
        components.queryItems = components.queryItems.map { $0 + queryItems } ?? queryItems
        self = components.url!
    }
}

/// As `URLSession` returns 3-values-tuple for request execution, this function applies consistency constraints and turns
/// it into only two possible states of `HTTPTransportResult`.
private func httpClientResult(for urlSessionTaskCompletion: (Data?, URLResponse?, Error?)) -> Result<HTTPURLResponse, HTTPClient.RequestError> {
    let (body, response, error) = urlSessionTaskCompletion

    if let error = error {
        return .failure(.transport(error))
    }

    guard let response = response as? HTTPURLResponse else {
        return .failure(.inconsistentResponse)
    }
    
    if let httpError = HTTPClient.RequestError(response: response, body: body) {
        return .failure(httpError)
    }

    return .success(response)
}

/// As `URLSession` returns 3-values-tuple for request execution, this function applies consistency constraints and turns
/// it into only two possible states of `HTTPTransportResult`.
private func httpClientResultWithData(for urlSessionTaskCompletion: (Data?, URLResponse?, Error?)) -> Result<Data, HTTPClient.RequestError> {
    let (data, response, error) = urlSessionTaskCompletion

    if let error = error {
        return .failure(.transport(error))
    }
    
    guard let response = response as? HTTPURLResponse else {
        return .failure(.inconsistentResponse)
    }
    
    if let httpError = HTTPClient.RequestError(response: response, body: data) {
        return .failure(httpError)
    }
    
    guard let data = data else {
        return .failure(.inconsistentResponse)
    }
    
    return .success(data)
}
