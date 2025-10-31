//
//  LogsApi.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 30/10/2025.
//

import Foundation

protocol LogsApi: APIService {
//    func uploadLogs(batch: //Create batch type,
//                    _ response: @escaping (Result<Void, APICallError>) -> Void)
    
    func uploadLogs(batch url: URL,
                    _ response: @escaping (Result<Void, APICallError>) -> Void)
    
    func uploadLogs(batch data: Data,
                    _ response: @escaping (Result<Void, HTTPClient.RequestError>) -> Void)
}

extension LogsApi {
    func uploadLogs(batch url: URL,
                    _ response: @escaping (Result<Void, APICallError>) -> Void)
    {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            uploadLogs(batch: data) { res in
                response(res.mapError(APICallError.init))
            }
        } catch {
            response(.failure(.fileSystem(error)))
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
    
    func uploadLogs(batch data: Data, _ response: @escaping (Result<Void, HTTPClient.RequestError>) -> Void) {
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
        httpClient.send(request: request) {
            log.debug("Logs upload result: \($0)")
            response($0.map { _ in })
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
