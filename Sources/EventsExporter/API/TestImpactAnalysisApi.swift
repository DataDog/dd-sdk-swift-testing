//
//  TestImpactAnalysisApi.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 30/10/2025.
//

import Foundation

protocol TestImpactAnalysisApi: APIService {
    func skippableTests(repositoryURL: String, sha: String,
                        environment: String, service: String,
                        tiaLevel: TIALevel, configurations: [String: String],
                        customConfigurations: [String: String],
                        _ response: @escaping (Result<SkipTests2, APICallError>) -> Void)
    
    func uploadCoverage(batch: TestCodeCoverage.Batch,
                        _ response: @escaping (Result<Void, APICallError>) -> Void)
    
    func uploadCoverage(batch url: URL,
                        _ response: @escaping (Result<Void, APICallError>) -> Void)
    
    func uploadCoverage(batch data: Data,
                        _ response: @escaping (Result<Void, HTTPClient.RequestError>) -> Void)
}

extension TestImpactAnalysisApi {
    func uploadCoverage(batch: TestCodeCoverage.Batch,
                        _ response: @escaping (Result<Void, APICallError>) -> Void)
    {
        do {
            let data = try encoder.encode(batch)
            uploadCoverage(batch: data) { res in
                response(res.mapError(APICallError.init))
            }
        } catch let err as EncodingError {
            response(.failure(.encoding(err)))
        } catch {
            response(.failure(.unknownError(error)))
        }
    }
    
    func uploadCoverage(batch url: URL,
                        _ response: @escaping (Result<Void, APICallError>) -> Void)
    {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            uploadCoverage(batch: data) { res in
                response(res.mapError(APICallError.init))
            }
        } catch {
            response(.failure(.fileSystem(error)))
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
    struct Batch: Encodable {
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
                        customConfigurations: [String: String],
                        _ response: @escaping (Result<SkipTests2, APICallError>) -> Void)
    {
        var configurations: [String: JSONGeneric] = configurations.mapValues { .string($0) }
        configurations["custom"] = .stringDict(customConfigurations)
        
        let request = TestsRequest(env: environment, service: service,
                                   repositoryUrl: repositoryURL, sha: sha,
                                   configurations: configurations,
                                   testLevel: tiaLevel)
        let log = self.log
        log.debug("Skippable tests request: \(request)")
        httpClient.call(TestsCall.self,
                        url: endpoint.skippableTestsURL,
                        data: .init(attributes: request),
                        headers: headers + [.contentTypeHeader(contentType: .applicationJSON)],
                        coders: (encoder, decoder))
        {
            log.debug("Skippable tests response: \($0)")
            response($0.map { SkipTests2(correlationId: $0.meta.correlationId,
                                         tests: $0.data.attributes) })
        }
    }
    
    func uploadCoverage(batch data: Data,
                        _ response: @escaping (Result<Void, HTTPClient.RequestError>) -> Void)
    {
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
        httpClient.send(request: request) {
            log.debug("Coverage batch upload response: \($0)")
            response($0.map { _ in })
        }
    }
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
