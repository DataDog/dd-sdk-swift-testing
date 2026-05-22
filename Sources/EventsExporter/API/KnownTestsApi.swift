/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public typealias KnownTestsMap = [String: [String: [String]]]

/// Result of a Known Tests API call
public struct KnownTestsResult {
    public let tests: KnownTestsMap
    public let pageInfo: KnownTestsPageInfo

    public init(tests: KnownTestsMap, pageInfo: KnownTestsPageInfo) {
        self.tests = tests
        self.pageInfo = pageInfo
    }

    public var isAllTests: Bool { !pageInfo.hasNext }
}

/// Pagination metadata from the Known Tests API (cursor for next page, page size, size, has_next).
public struct KnownTestsPageInfo {
    public let cursor: String?
    public let pageSize: Int
    public let size: Int
    public let hasNext: Bool

    public init(cursor: String?, pageSize: Int, size: Int, hasNext: Bool) {
        self.cursor = cursor
        self.pageSize = pageSize
        self.size = size
        self.hasNext = hasNext
    }

    public init(pageSize: Int = 2000) {
        self.pageSize = pageSize
        self.size = 0
        self.hasNext = false
        self.cursor = nil
    }
}

internal protocol KnownTestsApi: APIService {
    /// Fetch a single page of known tests for the provided cursor.
    func tests(
        service: String, env: String, repositoryURL: String,
        configurations: [String: String],
        customConfigurations: [String: String],
        page: KnownTestsPageInfo
    ) async throws(APICallError) -> KnownTestsResult

    /// Fetch all pages of known tests and merge them.
    func tests(
        service: String, env: String, repositoryURL: String,
        configurations: [String: String],
        customConfigurations: [String: String]
    ) async throws(APICallError) -> KnownTestsResult
}

extension KnownTestsApi {
    func tests(
        service: String, env: String, repositoryURL: String,
        configurations: [String: String],
        customConfigurations: [String: String]
    ) async throws(APICallError) -> KnownTestsResult {
        var tests: KnownTestsMap = [:]
        var page: KnownTestsPageInfo = .init()
        var size: Int = 0
        repeat {
            let result = try await self.tests(
                service: service, env: env, repositoryURL: repositoryURL,
                configurations: configurations, customConfigurations: customConfigurations,
                page: page
            )
            tests = tests.merging(result.tests) { (current, new) in
                current.merging(new) { (current, new) in
                    Array(Set(current).union(new))
                }
            }
            page = result.pageInfo
            size += result.pageInfo.size
        } while page.hasNext

        return KnownTestsResult(tests: tests,
                                pageInfo: .init(cursor: page.cursor,
                                                pageSize: page.pageSize,
                                                size: size,
                                                hasNext: page.hasNext))
    }
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
               page: KnownTestsPageInfo) async throws(APICallError) -> KnownTestsResult
    {
        var configurations: [String: JSONGeneric] = configurations.mapValues { .string($0) }
        configurations["custom"] = JSONGeneric(customConfigurations)

        let request = TestsRequest(repositoryUrl: repositoryURL, env: env,
                                   service: service, configurations: configurations,
                                   pageInfo: .init(pageSize: page.pageSize, pageState: page.cursor))
        let log = self.log
        log.debug("Known tests request: \(request)")
        let response = try await httpClient.call(KnownTestsCall.self,
                                                 url: endpoint.knownTestsURL,
                                                 data: .init(attributes: request),
                                                 headers: headers + [.contentTypeHeader(contentType: .applicationJSON)],
                                                 coders: (encoder, decoder))
        log.debug("Known tests response: \(response.data.attributes)")
        let attrs = response.data.attributes
        return KnownTestsResult(
            tests: attrs.tests,
            pageInfo: .init(cursor: attrs.pageInfo.cursor,
                            pageSize: page.pageSize,
                            size: attrs.pageInfo.size,
                            hasNext: attrs.pageInfo.hasNext)
        )
    }

    var endpointURLs: Set<URL> { [endpoint.knownTestsURL] }
}

extension KnownTestsApiService {
    struct PageInfoRequest: Encodable, CustomDebugStringConvertible {
        let pageSize: Int
        let pageState: String?

        var debugDescription: String {
            let state = pageState.map { #""\#($0)""# } ?? "null"
            return #"{"page_size": \#(pageSize), "page_state": \#(state)}"#
        }
    }

    struct PageInfoResponse: Decodable, CustomDebugStringConvertible {
        let cursor: String?
        let size: Int
        let hasNext: Bool

        var debugDescription: String {
            let cursorStr = cursor.map { #""\#($0)""# } ?? "null"
            return #"{"cursor": \#(cursorStr), "size": \#(size), "has_next": \#(hasNext)}"#
        }
    }

    struct TestsRequest: Encodable, APIAttributesUUID, CustomDebugStringConvertible {
        let repositoryUrl: String
        let env: String
        let service: String
        let configurations: [String: JSONGeneric]
        let pageInfo: PageInfoRequest

        static var apiType: String = "ci_app_libraries_tests_request"

        var debugDescription: String {
            let configs = JSONGeneric.object(configurations).debugDescription
            return #"{"repository_url": "\#(repositoryUrl)""#
                + #", "env": "\#(env)""#
                + #", "service": "\#(service)""#
                + #", "configurations": \#(configs)"#
                + #", "page_info": \#(pageInfo)}"#
        }
    }

    struct TestsResponse: Decodable, APIResponseAttributesHasType,
                          APIResponseAttributesBrokenId, CustomDebugStringConvertible
    {
        let tests: KnownTestsMap
        let pageInfo: PageInfoResponse

        static var apiType: String = "ci_app_libraries_tests"

        var debugDescription: String {
            let modules = tests.map { module, suites -> String in
                let suiteEntries = suites.map { suite, names -> String in
                    let testList = names.map { #""\#($0)""# }.joined(separator: ", ")
                    return #""\#(suite)": [\#(testList)]"#
                }.joined(separator: ", ")
                return #""\#(module)": {\#(suiteEntries)}"#
            }.joined(separator: ", ")
            return #"{"tests": {\#(modules)}, "page_info": \#(pageInfo)}"#
        }
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
