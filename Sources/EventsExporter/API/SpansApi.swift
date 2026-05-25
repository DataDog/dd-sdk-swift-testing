/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal protocol SpansApi: APIService {
    func uploadSpans(batch url: URL) async throws(APICallError)
    func uploadSpans(batch data: Data) async throws(HTTPClient.RequestError)
}

extension SpansApi {
    func uploadSpans(batch url: URL) async throws(APICallError) {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw .fileSystem(error)
        }
        do {
            try await uploadSpans(batch: data)
        } catch {
            throw APICallError(from: error)
        }
    }
}

struct SpansApiService: SpansApi {
    var endpoint: Endpoint
    var headers: [HTTPHeader]
    var encoder: JSONEncoder
    var decoder: JSONDecoder
    let compression: Bool
    let httpClient: HTTPClient
    let log: Logger

    init(config: APIServiceConfig, httpClient: HTTPClient, log: Logger) {
        self.endpoint = config.endpoint
        self.httpClient = httpClient
        self.log = log
        self.compression = config.payloadCompression
        self.headers = config.defaultHeaders
        self.encoder = config.encoder
        self.decoder = config.decoder
    }

    func uploadSpans(batch data: Data) async throws(HTTPClient.RequestError) {
        var request = URLRequest(url: endpoint.spansURL)
        request.httpMethod = "POST"
        request.httpHeaders = headers
        request.setHTTPHeader(.contentTypeHeader(contentType: .applicationJSON))
        if compression {
            request.setHTTPHeader(.contentEncodingHeader(contentEncoding: .deflate))
        }
        request.httpBody = data
        let log = self.log
        log.debug("Uploading spans...")
        let _ = try await httpClient.send(request: request)
        log.debug("Spans upload succeeded")
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
