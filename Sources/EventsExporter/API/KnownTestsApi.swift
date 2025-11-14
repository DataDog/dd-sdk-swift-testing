//
//  KnownTestsApi.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 28/10/2025.
//

import Foundation

public typealias KnownTestsMap2 = [String: [String: [String]]]

public protocol KnownTestsApi: APIService {
    func tests(
        service: String,
        env: String,
        repositoryURL: String,
        configurations: [String: String],
        customConfigurations: [String: String]) -> AsyncResult<KnownTestsMap2, APICallError>
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
               customConfigurations: [String: String]) -> AsyncResult<KnownTestsMap2, APICallError>
    {
        var configurations: [String: JSONGeneric] = configurations.mapValues { .string($0) }
        configurations["custom"] = .stringDict(customConfigurations)
        
        let request = TestsRequest(repositoryUrl: repositoryURL, env: env,
                                   service: service, configurations: configurations)
        let log = self.log
        log.debug("Known tests request: \(request)")
        return httpClient.call(KnownTestsCall.self,
                        url: endpoint.knownTestsURL,
                        data: .init(attributes: request),
                        headers: headers + [.contentTypeHeader(contentType: .applicationJSON)],
                        coders: (encoder, decoder))
            .peek { log.debug("Known tests response: \($0)") }
            .mapValue { $0.data.attributes.tests }
    }
    
    var endpointURLs: Set<URL> { [endpoint.knownTestsURL] }
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

private extension Endpoint {
    var knownTestsURL: URL {
        let endpoint = "/api/v2/ci/libraries/tests"
        switch self {
        case let .other(testsBaseURL: url, logsBaseURL: _): return url.appendingPathComponent(endpoint)
        default: return mainApi(endpoint: endpoint)!
        }
    }
}
