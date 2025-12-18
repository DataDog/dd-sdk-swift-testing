//
//  TestManagementApi.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 28/10/2025.
//

import Foundation

public protocol TestManagementApi: APIService {
    func tests(
        repositoryURL: String, sha: String?, commitMessage: String?, branch: String?, module: String?
    ) -> AsyncResult<TestManagementTestsInfo, APICallError>
}


public struct TestManagementTestsInfo: Codable {
    public let modules: [String: Module]
    
    public init(modules: [String : Module]) {
        self.modules = modules
    }
    
    public struct Module: Codable {
        public let suites: [String: Suite]
        
        public init(suites: [String : Suite]) {
            self.suites = suites
        }
    }

    public struct Suite: Codable {
        public let tests: [String: Test]
        
        public init(tests: [String : Test]) {
            self.tests = tests
        }
    }

    public struct Test: Codable {
        public let properties: Properties
        
        public init(properties: Properties) {
            self.properties = properties
        }
        
        public init() {
            self.init(properties: .init())
        }
        
        public init(disabled: Bool = false, quarantined: Bool = false, attemptToFix: Bool = false) {
            self.init(properties: .init(disabled: disabled,
                                        quarantined: quarantined,
                                        attemptToFix: attemptToFix))
        }
    }
    
    public struct Properties: Codable {
        public let disabled: Bool
        public let quarantined: Bool
        public let attemptToFix: Bool
        
        public init(disabled: Bool = false, quarantined: Bool = false, attemptToFix: Bool = false) {
            self.disabled = disabled
            self.quarantined = quarantined
            self.attemptToFix = attemptToFix
        }
    }
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
    
    func tests(repositoryURL: String, sha: String?, commitMessage: String?,
               branch: String?, module: String?) -> AsyncResult<TestManagementTestsInfo, APICallError>
    {
        let request = TestsRequest(repositoryUrl: repositoryURL,
                                   commitMessage: commitMessage,
                                   module: module,
                                   branch: branch,
                                   sha: sha)
        let log = self.log
        log.debug("TestManagement tests request: \(request)")
        return httpClient.call(TestsCall.self,
                        url: endpoint.testManagementTestsURL,
                        data: .init(attributes: request),
                        headers: headers + [.contentTypeHeader(contentType: .applicationJSON)],
                        coders: (encoder, decoder))
            .peek { log.debug("TestManamement tests response: \($0)") }
            .map { .init(modules: $0.data.attributes.modules) }
    }
    
    var endpointURLs: Set<URL> { [endpoint.testManagementTestsURL] }
}

extension TestManagementApiService {
    struct TestsRequest: Encodable, APIAttributesUUID {
        let repositoryUrl: String
        let commitMessage: String?
        let module: String?
        let branch: String?
        let sha: String?
        
        static var apiType: String = "ci_app_libraries_tests_request"
    }
    
    struct TestsResponse: Decodable, APIAttributes {
        let modules: [String: TestManagementTestsInfo.Module]
        
        static var apiType: String = "ci_app_libraries_tests"
    }
}

private extension Endpoint {
    var testManagementTestsURL: URL {
        let endpoint = "/api/v2/test/libraries/test-management/tests"
        switch self {
        case let .other(testsBaseURL: url, logsBaseURL: _): return url.appendingPathComponent(endpoint)
        default: return mainApi(endpoint: endpoint)!
        }
    }
}


