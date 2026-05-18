/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public enum ITRTestLevel: String, Codable {
    case test
    case suite
}

public struct SkipTests: Codable {
    public let correlationId: String
    public let tests: [SkipTestPublicFormat]

    public init(correlationId: String, tests: [SkipTestPublicFormat]) {
        self.correlationId = correlationId
        self.tests = tests
    }
}

public struct SkipTestPublicFormat: CustomStringConvertible, Codable {
    public var name: String
    public var suite: String
    public var configuration: [String: String]?
    public var customConfiguration: [String: String]?

    public var description: String {
        return "{name:\(name), suite:\(suite), configuration: \(configuration ?? [:]), customConfiguration: \(customConfiguration ?? [:])}"
    }

    public init(name: String, suite: String,
                configuration: [String : String]? = nil,
                customConfiguration: [String : String]? = nil)
    {
        self.name = name
        self.suite = suite
        self.configuration = configuration
        self.customConfiguration = customConfiguration
    }
}

internal protocol TestImpactAnalysisApi: APIService {
    func skippableTests(repositoryURL: String, sha: String,
                        environment: String, service: String,
                        testLevel: ITRTestLevel, configurations: [String: String],
                        customConfigurations: [String: String]) async throws(APICallError) -> SkipTests

    func uploadCoverage(batch url: URL) async throws(APICallError)
    func uploadCoverage(batch data: Data) async throws(HTTPClient.RequestError)
}

extension TestImpactAnalysisApi {
    func uploadCoverage(batch url: URL) async throws(APICallError) {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw .fileSystem(error)
        }
        do {
            try await uploadCoverage(batch: data)
        } catch {
            throw APICallError(from: error)
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
                        testLevel: ITRTestLevel, configurations: [String: String],
                        customConfigurations: [String: String]) async throws(APICallError) -> SkipTests
    {
        var configurations: [String: JSONGeneric] = configurations.mapValues { .string($0) }
        configurations["custom"] = JSONGeneric(customConfigurations)

        let request = TestsRequest(env: environment, service: service,
                                   repositoryUrl: repositoryURL, sha: sha,
                                   configurations: configurations,
                                   testLevel: testLevel)
        let log = self.log
        log.debug("Skippable tests request: \(request)")
        let response = try await httpClient.call(TestsCall.self,
                                                 url: endpoint.skippableTestsURL,
                                                 data: .init(attributes: request),
                                                 headers: headers + [.contentTypeHeader(contentType: .applicationJSON)],
                                                 coders: (encoder, decoder))
        log.debug("Skippable tests response: \(response.data)")
        let correlationId = response.meta.correlationId
        let tests = response.data.attributes.map { test in
            let customConfiguration = test.configurations?["custom"].flatMap {
                switch $0 {
                case .object(let dict):
                    return dict.compactMapValues {
                        switch $0 {
                        case .string(let s): return s
                        default: return nil
                        }
                    }
                default: return nil
                }
            }
            let configuration: [String: String]? = test.configurations?.compactMapValues {
                switch $0 {
                case .string(let s): return s
                default: return nil
                }
            }
            return SkipTestPublicFormat(name: test.name,
                                        suite: test.suite,
                                        configuration: configuration,
                                        customConfiguration: customConfiguration)
        }
        return SkipTests(correlationId: correlationId, tests: tests)
    }

    func uploadCoverage(batch data: Data) async throws(HTTPClient.RequestError) {
        var request = MultipartFormURLRequest(url: endpoint.coverageURL)
        request.headers = headers
        request.append(data: data,
                       withName: "coverage",
                       filename: "CoverageBatch.json",
                       contentType: .applicationJSON)
        request.append(data: Data("{\"dummy\": true}".utf8),
                       withName: "event",
                       filename: "DummyEvent.json",
                       contentType: .applicationJSON)
        let log = self.log
        log.debug("Uploading coverage batch...")
        let response = try await httpClient.send(request: request)
        log.debug("Coverage batch upload response: \(response.statusCode)")
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
        let testLevel: ITRTestLevel

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

extension Endpoint {
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
