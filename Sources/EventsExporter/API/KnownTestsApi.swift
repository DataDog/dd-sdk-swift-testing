//
//  KnownTestsApi.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 28/10/2025.
//

import Foundation

public typealias KnownTestsMap2 = [String: [String: [String]]]

protocol KnownTestsApi: APIService {
    func tests(
        service: String,
        env: String,
        repositoryURL: String,
        configurations: [String: String],
        customConfigurations: [String: String],
        _ response: @escaping (Result<KnownTestsMap2, APICallError>) -> Void)
}

struct KnownTestsApiService: KnownTestsApi {
    typealias KnownTestsCall = APICall<APIDataNoMeta<TestsRequest>, APIDataNoMeta<TestsResponse>>
    
    var endpoint: Endpoint
    var headers: [HTTPHeader]
    var encoder: JSONEncoder
    var decoder: JSONDecoder
    let httpClient: HTTPClient
    let log: Logger
    
    init(config: APIServiceConfig, httpClient: HTTPClient, log: Logger) {
        self.endpoint = config.endpoint
        self.httpClient = httpClient
        self.log = log
        self.headers = config.defaultHeaders
        self.encoder = config.encoder
        self.decoder = config.decoder
    }
    
    func tests(service: String, env: String,
               repositoryURL: String,
               configurations: [String: String],
               customConfigurations: [String: String],
               _ response: @escaping (Result<KnownTestsMap2, APICallError>) -> Void)
    {
        var configurations: [String: JSONGeneric] = configurations.mapValues { .string($0) }
        configurations["custom"] = .stringDict(customConfigurations)
        
        let request = TestsRequest(repositoryUrl: repositoryURL, env: env,
                                   service: service, configurations: configurations)
        let log = self.log
        log.debug("Known tests request: \(request)")
        httpClient.call(KnownTestsCall.self,
                        url: endpoint.knownTestsURL,
                        data: .init(attributes: request),
                        headers: headers + [.contentTypeHeader(contentType: .applicationJSON)],
                        coders: (encoder, decoder))
        {
            log.debug("Known tests response: \($0)")
            response($0.map { $0.data.attributes.tests })
        }
    }
}

extension KnownTestsApiService {
    struct TestsRequest: Encodable, APIAttributesUUID {
        let repositoryUrl: String
        let env: String
        let service: String
        let configurations: [String: JSONGeneric]
        
        static var apiType: String = "ci_app_libraries_tests_request"
    }
    
    struct TestsResponse: Decodable, APIAttributes {
        let tests: KnownTestsMap2
        
        static var apiType: String = "ci_app_libraries_tests"
    }
}
