//
//  LogsApi.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 30/10/2025.
//

import Foundation

public protocol LogsApi: APIService {
//    func uploadLogs(batch: //Create batch type,
//                    _ response: @escaping (Result<Void, APICallError>) -> Void)
    
    func uploadLogs(batch url: URL) -> AsyncResult<Void, APICallError>
    func uploadLogs(batch data: Data) -> AsyncResult<Void, HTTPClient.RequestError>
}

extension LogsApi {
    func uploadLogs(batch url: URL) -> AsyncResult<Void, APICallError> {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return uploadLogs(batch: data).mapError(APICallError.init)
        } catch {
            return .error(.fileSystem(error))
        }
    }
    
//    func uploadLogs(batch: //Create batch type,
//                    _ response: @escaping (Result<Void, APICallError>) -> Void)
}

struct LogsApiService: LogsApi {
    var endpoint: Endpoint
    var headers: [HTTPHeader]
    var encoder: JSONEncoder
    var decoder: JSONDecoder
    let httpClient: HTTPClient
    let log: Logger
    
    init(config: APIServiceConfig, httpClient: HTTPClient, log: any Logger) {
        self.endpoint = config.endpoint
        self.httpClient = httpClient
        self.log = log
        self.headers = config.defaultHeaders
        self.encoder = config.encoder
        self.decoder = config.decoder
    }
    
    func uploadLogs(batch data: Data) -> AsyncResult<Void, HTTPClient.RequestError> {
        var url = endpoint.logsURL
        url.appendQueryItems([
            .ddsource(source: LogQueryValues.ddsource),
            .ddtags(tags: [LogQueryValues.ddproduct])
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpHeaders = headers
        request.setHTTPHeader(.contentTypeHeader(contentType: .applicationJSON))
        request.httpBody = data
        let log = self.log
        log.debug("Uploading logs...")
        return httpClient.send(request: request).peek {
            log.debug("Logs upload result: \($0)")
        }.asVoid
    }
    
    var endpointURLs: Set<URL> { [endpoint.logsURL] }
}

private extension Endpoint {
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

extension URLQueryItem {
    /// `ddsource={source}` query item
    static func ddsource(source: String) -> URLQueryItem {
        URLQueryItem(name: "ddsource", value: source)
    }
    /// `ddtags={tag1},{tag2},...` query item
    static func ddtags(tags: [String]) -> URLQueryItem {
        URLQueryItem(name: "ddtags", value: tags.joined(separator: ","))
    }
}
