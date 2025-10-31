//
//  TestManagementApi.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 28/10/2025.
//

import Foundation

protocol TestManagementApi: APIService {
    func tests(
        repositoryURL: String, sha: String?, commitMessage: String?, module: String?,
        _ response: @escaping (Result<TestManagementTestsInfo, APICallError>) -> Void
    )
}

struct TestManagementApiService: TestManagementApi {
    typealias TestsCall = APICall<APIDataNoMeta<TestsRequest>, APIDataNoMeta<TestsResponse>>
    
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
    
    func tests(repositoryURL: String, sha: String?, commitMessage: String?, module: String?,
               _ response: @escaping (Result<TestManagementTestsInfo, APICallError>) -> Void)
    {
        let request = TestsRequest(repositoryUrl: repositoryURL,
                                   commitMessage: commitMessage,
                                   module: module,
                                   sha: sha)
        let log = self.log
        log.debug("TestManagement tests request: \(request)")
        httpClient.call(TestsCall.self,
                        url: endpoint.testManagementTestsURL,
                        data: .init(attributes: request),
                        headers: headers + [.contentTypeHeader(contentType: .applicationJSON)],
                        coders: (encoder, decoder))
        {
            log.debug("TestManamement tests response: \($0)")
            response($0.map { .init(modules: $0.data.attributes.modules) })
        }
    }
}

extension TestManagementApiService {
    struct TestsRequest: Encodable, APIAttributesUUID {
        let repositoryUrl: String
        let commitMessage: String?
        let module: String?
        let sha: String?
        
        static var apiType: String = "ci_app_libraries_tests_request"
    }
    
    struct TestsResponse: Decodable, APIAttributes {
        let modules: [String: TestManagementTestsInfo.Module]
        
        static var apiType: String = "ci_app_libraries_tests"
    }
}
