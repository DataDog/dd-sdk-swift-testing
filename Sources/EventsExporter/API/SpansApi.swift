/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public protocol SpansApi: APIService {
    func uploadSpans(batch url: URL, observer: RequestObserver?, timeout: TimeInterval?) async throws(APICallError)
    func uploadSpans(batch data: Data, observer: RequestObserver?, timeout: TimeInterval?) async throws(APICallError)
    func uploadSpans(batch data: Data, observer: RequestObserver?, timeout: TimeInterval?) throws(APICallError)
}

extension SpansApi {
    public func uploadSpans(batch url: URL, observer: RequestObserver? = nil, timeout: TimeInterval? = nil) async throws(APICallError) {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw .fileSystem(error)
        }
        try await uploadSpans(batch: data, observer: observer, timeout: timeout)
    }

    /// Convenience without telemetry observer and timeout.
    @inlinable
    public func uploadSpans(batch data: Data) async throws(APICallError) {
        try await uploadSpans(batch: data, observer: nil, timeout: nil)
    }
    
    /// Convenience without timeout.
    @inlinable
    public func uploadSpans(batch data: Data, observer: RequestObserver?) async throws(APICallError) {
        try await uploadSpans(batch: data, observer: observer, timeout: nil)
    }
    
    /// Convenience without telemetry observer.
    @inlinable
    public func uploadSpans(batch data: Data, timeout: TimeInterval?) async throws(APICallError) {
        try await uploadSpans(batch: data, observer: nil, timeout: timeout)
    }
    
    /// Convenience without telemetry observer and timeaout.
    @inlinable
    public func uploadSpans(batch data: Data) throws(APICallError) {
        try uploadSpans(batch: data, observer: nil, timeout: nil)
    }
    
    /// Convenience without timeout.
    @inlinable
    public func uploadSpans(batch data: Data, observer: RequestObserver?) throws(APICallError) {
        try uploadSpans(batch: data, observer: observer, timeout: nil)
    }
    
    /// Convenience without telemetry observer.
    @inlinable
    public func uploadSpans(batch data: Data, timeout: TimeInterval?) throws(APICallError) {
        try uploadSpans(batch: data, observer: nil, timeout: timeout)
    }
}

struct SpansApiService: SpansApi, APIServiceConstructible {
    var endpoint: Endpoint
    var headers: [HTTPHeader]
    var encoder: JSONEncoder
    var decoder: JSONDecoder
    let compression: Bool
    let httpClient: any HTTPClientType

    init(config: APIServiceConfig, httpClient: any HTTPClientType, log: Logger) {
        self.endpoint = config.endpoint
        self.httpClient = httpClient
        self.compression = config.payloadCompression
        self.headers = config.defaultHeaders
        self.encoder = config.encoder
        self.decoder = config.decoder
    }

    func uploadSpans(batch data: Data, observer: RequestObserver?, timeout: TimeInterval?) async throws(APICallError) {
        try await httpClient.send(api: _spansRequest(batch: data, timeout: timeout), observer: observer)
    }

    func uploadSpans(batch data: Data, observer: RequestObserver?, timeout: TimeInterval?) throws(APICallError) {
        try httpClient.send(api: _spansRequest(batch: data, timeout: timeout), observer: observer)
    }

    var endpointURLs: Set<URL> { [endpoint.spansURL] }
    
    private func _spansRequest(batch data: Data, timeout: TimeInterval?) -> URLRequest {
        var request = URLRequest(url: endpoint.spansURL)
        request.httpMethod = "POST"
        request.httpHeaders = headers
        request.setHTTPHeader(.contentTypeHeader(contentType: .applicationJSON))
        if compression {
            request.setHTTPHeader(.contentEncodingHeader(contentEncoding: .deflate))
        }
        request.httpBody = data
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

extension Endpoint {
    var spansURL: URL {
        let endpoint = "/api/v2/citestcycle"
        switch self {
        case let .other(testsBaseURL: url, logsBaseURL: _): return url.appendingPathComponent(endpoint)
        default: return URL(string: "https://citestcycle-intake.\(site!)\(endpoint)")!
        }
    }
}
