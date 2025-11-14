//
//  SpansApi.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 30/10/2025.
//

import Foundation

public protocol SpansApi: APIService {
//    func uploadSpans(batch: //Create batch type,
//                     _ response: @escaping (Result<Void, APICallError>) -> Void)
    
    func uploadSpans(batch url: URL) -> AsyncResult<Void, APICallError>
    func uploadSpans(batch data: Data) -> AsyncResult<Void, HTTPClient.RequestError>
}

extension SpansApi {
    func uploadSpans(batch url: URL) -> AsyncResult<Void, APICallError> {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return uploadSpans(batch: data).mapError(APICallError.init)
        } catch {
            return .error(.fileSystem(error))
        }
    }
    
//    func uploadSpans(batch: //Create batch type,
//                     _ response: @escaping (Result<Void, APICallError>) -> Void)
}

struct SpansApiService: SpansApi {
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
    
    func uploadSpans(batch data: Data) -> AsyncResult<Void, HTTPClient.RequestError> {
        var request = URLRequest(url: endpoint.spansURL)
        request.httpMethod = "POST"
        request.httpHeaders = headers
        request.setHTTPHeader(.contentTypeHeader(contentType: .applicationJSON))
        request.httpBody = data
        let log = self.log
        log.debug("Uploading spans...")
        return httpClient.send(request: request).peek {
            log.debug("Spans upload result: \($0)")
        }.asVoid
    }
    
    var endpointURLs: Set<URL> { [endpoint.spansURL] }
}

private extension Endpoint {
    var spansURL: URL {
        let endpoint = "/api/v2/citestcycle"
        switch self {
        case let .other(testsBaseURL: url, logsBaseURL: _): return url.appendingPathComponent(endpoint)
        default: return URL(string: "https://citestcycle-intake.\(site!)\(endpoint)")!
        }
    }
}
