//
//  TestImpactAnalysisApi.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 30/10/2025.
//

import Foundation

public protocol TestImpactAnalysisApi: APIService {
    func skippableTests(repositoryURL: String, sha: String,
                        environment: String, service: String,
                        tiaLevel: TIALevel, configurations: [String: String],
                        customConfigurations: [String: String]) -> AsyncResult<SkipTests2, APICallError>
    
    func uploadCoverage(batch: TestCodeCoverage.Batch) -> AsyncResult<Void, APICallError>
    
    func uploadCoverage(batch url: URL) -> AsyncResult<Void, APICallError>
    
    func uploadCoverage(batch data: Data) -> AsyncResult<Void, HTTPClient.RequestError>
}

extension TestImpactAnalysisApi {
    func uploadCoverage(batch: TestCodeCoverage.Batch) -> AsyncResult<Void, APICallError> {
        do {
            let data = try encoder.encode(batch)
            return uploadCoverage(batch: data).mapError(APICallError.init)
        } catch let err as EncodingError {
            return .error(.encoding(err))
        } catch {
            return .error(.unknownError(error))
        }
    }
    
    func uploadCoverage(batch url: URL) -> AsyncResult<Void, APICallError> {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return uploadCoverage(batch: data).mapError(APICallError.init)
        } catch {
            return .error(.fileSystem(error))
        }
    }
}

public enum TIALevel: String, Codable {
    case test
    case suite
}

public struct SkipTests2: Codable {
    public struct Test: Codable, CustomDebugStringConvertible {
        public var name: String
        public var suite: String
        public var configurations: [String: String]?
        public var customConfigurations: [String: String]?
        
        public var module: String? { configurations?["test.bundle"] }
        public var debugDescription: String {
            "[name: \(name), suite: \(suite), configurations: \(configurations ?? [:]), customConfigurations: \(customConfigurations ?? [:])]"
        }
        
        public init(name: String, suite: String,
                    configurations: [String : String]? = nil,
                    customConfigurations: [String : String]? = nil)
        {
            self.name = name
            self.suite = suite
            self.configurations = configurations
            self.customConfigurations = customConfigurations
        }
    }
    
    public let correlationId: String
    public let tests: [Test]
    
    public init(correlationId: String, tests: [Test]) {
        self.correlationId = correlationId
        self.tests = tests
    }
    
    init(correlationId: String, tests: [TestImpactAnalysisApiService.TestsResponse]) {
        let skipTests = tests.map { test in
            let customConfigurations = test.configurations?["custom"].flatMap {
                switch $0 {
                case .stringDict(let dict): return dict
                default: return nil
                }
            }
            let configurations = test.configurations?.compactMapValues {
                switch $0 {
                case .string(let string): return string
                default: return nil
                }
            }
            return Test(name: test.name,
                        suite: test.suite,
                        configurations: configurations,
                        customConfigurations: customConfigurations)
        }
        self.init(correlationId: correlationId, tests: skipTests)
    }
}

extension TestCodeCoverage {
    public struct Batch: Encodable {
        let version: Int = 2
        let coverages: [TestCodeCoverage]
        
        init(coverages: [TestCodeCoverage]) {
            self.coverages = coverages
        }
    }
}

struct TestImpactAnalysisApiService: TestImpactAnalysisApi {
    typealias TestsCall = APICall<APIDataNoMeta<TestsRequest>, [APIData<TestsResponse.Meta, TestsResponse>]>
    
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
    
    func skippableTests(repositoryURL: String, sha: String,
                        environment: String, service: String,
                        tiaLevel: TIALevel, configurations: [String: String],
                        customConfigurations: [String: String])  -> AsyncResult<SkipTests2, APICallError> {
        var configurations: [String: JSONGeneric] = configurations.mapValues { .string($0) }
        configurations["custom"] = .stringDict(customConfigurations)
        
        let request = TestsRequest(env: environment, service: service,
                                   repositoryUrl: repositoryURL, sha: sha,
                                   configurations: configurations,
                                   testLevel: tiaLevel)
        let log = self.log
        log.debug("Skippable tests request: \(request)")
        return httpClient.call(TestsCall.self,
                        url: endpoint.skippableTestsURL,
                        data: .init(attributes: request),
                        headers: headers + [.contentTypeHeader(contentType: .applicationJSON)],
                        coders: (encoder, decoder))
            .peek { log.debug("Skippable tests response: \($0)") }
            .mapValue { SkipTests2(correlationId: $0.meta.correlationId,
                                   tests: $0.data.attributes) }
    }
    
    func uploadCoverage(batch data: Data) -> AsyncResult<Void, HTTPClient.RequestError> {
        let log = self.log
        var request = MultipartFormURLRequest(url: endpoint.coverageURL)
        request.headers = headers
        request.append(data: data,
                       withName: "coverage",
                       filename: "CoverageBatch.json",
                       contentType: .applicationJSON)
        request.append(data: "{\"dummy\": true}".data(using: .utf8)!,
                       withName: "event",
                       filename: "DummyEvent.json",
                       contentType: .applicationJSON)
        log.debug("Uploading coverage batch...")
        return httpClient.send(request: request).peek {
            log.debug("Coverage batch upload response: \($0)")
        }.asVoid
    }
    
    var endpointURLs: Set<URL> { [endpoint.skippableTestsURL, endpoint.coverageURL] }
}

extension TestImpactAnalysisApiService {
    struct TestsRequest: APIAttributesNoId, Encodable {
        let env: String
        let service: String
        let repositoryUrl: String
        let sha: String
        let configurations: [String: JSONGeneric]
        let testLevel: TIALevel
        
        static var apiType: String = "test_params"
    }
    
    struct TestsResponse: APIAttributes, Decodable {
        struct Meta: Decodable {
            let correlationId: String
        }
        
        let name: String
        let parameters: String?
        let suite: String
        let configurations: [String: JSONGeneric]?
        
        static var apiType: String = "test"
    }
}

private extension Endpoint {
    var skippableTestsURL: URL {
        let endpoint = "/api/v2/ci/tests/skippable"
        switch self {
        case let .other(testsBaseURL: url, logsBaseURL: _): return url.appendingPathComponent(endpoint)
        default: return mainApi(endpoint: endpoint)!
        }
    }
    
    var coverageURL: URL {
        let endpoint = "/api/v2/citestcov"
        switch self {
        case .other(testsBaseURL: let url, logsBaseURL: _): return url.appendingPathComponent(endpoint)
        default: return URL(string: "https://event-platform-intake.\(site!)\(endpoint)")!
        }
    }
}
