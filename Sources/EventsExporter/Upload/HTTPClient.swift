/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// Client for sending requests over HTTP.
internal final class HTTPClient {
    private let session: URLSession
    private let debug: Bool
    
    convenience init(debug: Bool) {
        let configuration: URLSessionConfiguration = .ephemeral
        // NOTE: RUMM-610 Default behaviour of `.ephemeral` session is to cache requests.
        // To not leak requests memory (including their `.httpBody` which may be significant)
        // we explicitly opt-out from using cache. This cannot be achieved using `.requestCachePolicy`.
        configuration.urlCache = nil
        // TODO: RUMM-123 Optimize `URLSessionConfiguration` for good traffic performance
        // and move session configuration constants to `PerformancePreset`.
        self.init(session: URLSession(configuration: configuration), debug: debug)
    }
    
    init(session: URLSession, debug: Bool) {
        self.session = session
        self.debug = debug
    }
    
    func send(request: URLRequest, completion: @escaping (Result<HTTPURLResponse, Error>) -> Void) {
        let task = session.dataTask(with: request) { data, response, error in
            self.log(request: request, response: (data, response, error))
            completion(httpClientResult(for: (data, response, error)))
        }
        task.resume()
    }
    
    func sendWithResult(request: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) {
        let task = session.dataTask(with: request) { data, response, error in
            self.log(request: request, response: (data, response, error))
            completion(httpClientResultWithData(for: (data, response, error)))
        }
        task.resume()
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
private func httpClientResult(for urlSessionTaskCompletion: (Data?, URLResponse?, Error?)) -> Result<HTTPURLResponse, Error> {
    let (_, response, error) = urlSessionTaskCompletion

    if let error = error {
        return .failure(error)
    }

    if let httpResponse = response as? HTTPURLResponse {
        return .success(httpResponse)
    }

    return .failure(URLSessionTransportInconsistencyException())
}

/// As `URLSession` returns 3-values-tuple for request execution, this function applies consistency constraints and turns
/// it into only two possible states of `HTTPTransportResult`.
private func httpClientResultWithData(for urlSessionTaskCompletion: (Data?, URLResponse?, Error?)) -> Result<Data, Error> {
    let (data, _ , error) = urlSessionTaskCompletion

    if let error = error {
        return .failure(error)
    }

    if let httpResponse = data {
        return .success(httpResponse)
    }

    return .failure(URLSessionTransportInconsistencyException())
}
