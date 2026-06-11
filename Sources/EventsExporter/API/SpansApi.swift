/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public protocol SpansApi: APIService {
    func uploadSpans(batch url: URL, observer: RequestObserver?) async throws(APICallError)
    func uploadSpans(batch data: Data, observer: RequestObserver?) async throws(APICallError)
}

extension SpansApi {
    public func uploadSpans(batch url: URL, observer: RequestObserver?) async throws(APICallError) {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw .fileSystem(error)
        }
        try await uploadSpans(batch: data, observer: observer)
    }

    /// Convenience without a telemetry observer.
    @inlinable
    public func uploadSpans(batch url: URL) async throws(APICallError) {
        try await uploadSpans(batch: url, observer: nil)
    }

    /// Convenience without a telemetry observer.
    @inlinable
    public func uploadSpans(batch data: Data) async throws(APICallError) {
        try await uploadSpans(batch: data, observer: nil)
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

    func uploadSpans(batch data: Data, observer: RequestObserver?) async throws(APICallError) {
        var request = URLRequest(url: endpoint.spansURL)
        request.httpMethod = "POST"
        request.httpHeaders = headers
        request.setHTTPHeader(.contentTypeHeader(contentType: .applicationJSON))
        if compression {
            request.setHTTPHeader(.contentEncodingHeader(contentEncoding: .deflate))
        }
        request.httpBody = data
        let _ = try await httpClient.send(api: request, observer: observer)
    }

    var endpointURLs: Set<URL> { [endpoint.spansURL] }
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
