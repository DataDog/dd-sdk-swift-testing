//
//  SpansApi.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 30/10/2025.
//

import Foundation

protocol SpansApi: APIService {
//    func uploadSpans(batch: //Create batch type,
//                     _ response: @escaping (Result<Void, APICallError>) -> Void)
    
    func uploadSpans(batch url: URL,
                     _ response: @escaping (Result<Void, APICallError>) -> Void)
    
    func uploadSpans(batch data: Data,
                     _ response: @escaping (Result<Void, HTTPClient.RequestError>) -> Void)
}

extension SpansApi {
    func uploadSpans(batch url: URL,
                     _ response: @escaping (Result<Void, APICallError>) -> Void)
    {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            uploadSpans(batch: data) { res in
                response(res.mapError(APICallError.init))
            }
        } catch {
            response(.failure(.fileSystem(error)))
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
    
    func uploadSpans(batch data: Data, _ response: @escaping (Result<Void, HTTPClient.RequestError>) -> Void) {
        var request = URLRequest(url: endpoint.spansURL)
        request.httpMethod = "POST"
        request.httpHeaders = headers
        request.setHTTPHeader(.contentTypeHeader(contentType: .applicationJSON))
        request.httpBody = data
        let log = self.log
        log.debug("Uploading spans...")
        httpClient.send(request: request) {
            log.debug("Spans upload result: \($0)")
            response($0.map { _ in })
        }
    }
}
