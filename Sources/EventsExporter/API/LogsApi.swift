/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public protocol LogsApi: APIService {
    func uploadLogs(batch url: URL, observer: RequestObserver?) async throws(APICallError)
    func uploadLogs(batch data: Data, observer: RequestObserver?) async throws(APICallError)
}

extension LogsApi {
    public func uploadLogs(batch url: URL, observer: RequestObserver?) async throws(APICallError) {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw .fileSystem(error)
        }
        try await uploadLogs(batch: data, observer: observer)
    }

    /// Convenience without a telemetry observer.
    @inlinable
    public func uploadLogs(batch url: URL) async throws(APICallError) {
        try await uploadLogs(batch: url, observer: nil)
    }

    /// Convenience without a telemetry observer.
    @inlinable
    public func uploadLogs(batch data: Data) async throws(APICallError) {
        try await uploadLogs(batch: data, observer: nil)
    }
}

struct LogsApiService: LogsApi, APIServiceConstructible {
    var endpoint: Endpoint
    var headers: [HTTPHeader]
    var encoder: JSONEncoder
    var decoder: JSONDecoder
    let httpClient: any HTTPClientType
    let compression: Bool

    init(config: APIServiceConfig, httpClient: any HTTPClientType, log: Logger) {
        self.endpoint = config.endpoint
        self.httpClient = httpClient
        self.compression = config.payloadCompression
        self.headers = config.defaultHeaders
        self.encoder = config.encoder
        self.decoder = config.decoder
    }

    func uploadLogs(batch data: Data, observer: RequestObserver?) async throws(APICallError) {
        var url = endpoint.logsURL
        url.appendQueryItems([
            .ddsource(source: LogQueryValues.ddsource),
            .ddtags(tags: [LogQueryValues.ddproduct]),
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpHeaders = headers
        request.setHTTPHeader(.contentTypeHeader(contentType: .applicationJSON))
        if compression {
            request.setHTTPHeader(.contentEncodingHeader(contentEncoding: .deflate))
        }
        request.httpBody = data
        let _ = try await httpClient.send(api: request, observer: observer)
    }

    var endpointURLs: Set<URL> { [endpoint.logsURL] }
}


extension Endpoint {
    var logsURL: URL {
        let endpoint = "/api/v2/logs"
        switch self {
        case .us1: return URL(string: "https://logs.browser-intake-datadoghq.com" + endpoint)!
        case .us3: return URL(string: "https://logs.browser-intake-us3-datadoghq.com" + endpoint)!
        case .us5: return URL(string: "https://logs.browser-intake-us5-datadoghq.com" + endpoint)!
        case .eu1: return URL(string: "https://mobile-http-intake.logs.datadoghq.eu" + endpoint)!
        case .ap1: return URL(string: "https://logs.browser-intake-ap1-datadoghq.com" + endpoint)!
        case .staging: return URL(string: "https://logs.browser-intake-datad0g.com" + endpoint)!
        case let .other(testsBaseURL: _, logsBaseURL: url): return url.appendingPathComponent(endpoint)
        }
    }
}

private enum LogQueryValues {
    static let ddsource = "ios"
    static let ddproduct = "datadog.product:citest"
}

private extension URLQueryItem {
    /// `ddsource={source}` query item
    static func ddsource(source: String) -> URLQueryItem {
        URLQueryItem(name: "ddsource", value: source)
    }
    /// `ddtags={tag1},{tag2},...` query item
    static func ddtags(tags: [String]) -> URLQueryItem {
        URLQueryItem(name: "ddtags", value: tags.joined(separator: ","))
    }
}

private extension URL {
    mutating func appendQueryItems(_ queryItems: [URLQueryItem]) {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: true)!
        components.queryItems = components.queryItems.map { $0 + queryItems } ?? queryItems
        self = components.url!
    }
}
