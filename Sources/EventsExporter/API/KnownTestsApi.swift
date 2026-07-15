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

/// Pagination metadata for the Known Tests API call (cursor for next page, page size).
public struct KnownTestsPageCursor: Encodable, CustomDebugStringConvertible {
    public let pageState: String?
    public let pageSize: Int?

    public init(pageSize: Int? = nil, pageState: String? = nil) {
        self.pageState = pageState
        self.pageSize = pageSize
    }
    
    public var debugDescription: String {
        let size = pageSize.map { "\($0)" } ?? "auto"
        let state = pageState.map { #""\#($0)""# } ?? "null"
        return #"{"page_size": \#(size), "page_state": \#(state)}"#
    }
}

/// Pagination metadata from the Known Tests API (cursor for next page, size, has_next).
public struct KnownTestsPageInfo: Decodable, CustomDebugStringConvertible {
    public let cursor: String?
    public let size: Int
    public let hasNext: Bool

    public init(cursor: String?, size: Int, hasNext: Bool) {
        self.cursor = cursor
        
        self.size = size
        self.hasNext = hasNext
    }
    
    public func next(pageSize: Int? = nil) -> KnownTestsPageCursor? {
        hasNext ? .init(pageSize: pageSize, pageState: cursor) : nil
    }
    
    public var debugDescription: String {
        let cursorStr = cursor.map { #""\#($0)""# } ?? "null"
        return #"{"cursor": \#(cursorStr), "size": \#(size), "has_next": \#(hasNext)}"#
    }
}

public protocol KnownTestsApi: APIService {
    /// Fetch a single page of known tests for the provided cursor.
    func tests(
        service: String, env: String, repositoryURL: String,
        configurations: [String: String],
        customConfigurations: [String: String],
        page: KnownTestsPageCursor,
        observer: RequestObserver?
    ) async throws(APICallError) -> KnownTestsResult

    /// Fetch all pages of known tests and merge them.
    func tests(
        service: String, env: String, repositoryURL: String,
        configurations: [String: String],
        customConfigurations: [String: String],
        observer: PagedRequestObserver?
    ) async throws(APICallError) -> KnownTestsMap
}

extension KnownTestsApi {
    public func tests(
        service: String, env: String, repositoryURL: String,
        configurations: [String: String],
        customConfigurations: [String: String],
        observer: PagedRequestObserver?
    ) async throws(APICallError) -> KnownTestsMap {
        let startTime = Date().timeIntervalSince1970 * 1000
        var tests: KnownTestsMap = [:]
        var page: KnownTestsPageCursor? = .init()

        repeat {
            let result = try await self.tests(
                service: service, env: env, repositoryURL: repositoryURL,
                configurations: configurations, customConfigurations: customConfigurations,
                page: page!, observer: observer
            )

            tests = tests.merging(result.tests) { (current, new) in
                current.merging(new) { (current, new) in
                    Array(Set(current).union(new))
                }
            }
            page = result.pageInfo.next()
        } while page != nil

        let totalFetchMs = Date().timeIntervalSince1970 * 1000 - startTime
        observer?.finished(totalFetchMs: totalFetchMs)

        return tests
    }

    /// Convenience without a telemetry observer.
    @inlinable
    public func tests(
        service: String, env: String, repositoryURL: String,
        configurations: [String: String],
        customConfigurations: [String: String],
        page: KnownTestsPageCursor
    ) async throws(APICallError) -> KnownTestsResult {
        try await tests(service: service, env: env, repositoryURL: repositoryURL,
                        configurations: configurations, customConfigurations: customConfigurations,
                        page: page, observer: nil)
    }

    /// Convenience without a telemetry observer.
    @inlinable
    public func tests(
        service: String, env: String, repositoryURL: String,
        configurations: [String: String],
        customConfigurations: [String: String]
    ) async throws(APICallError) -> KnownTestsMap {
        try await tests(service: service, env: env, repositoryURL: repositoryURL,
                        configurations: configurations, customConfigurations: customConfigurations,
                        observer: nil)
    }
}

struct KnownTestsApiService: KnownTestsApi, APIServiceConstructible {
    typealias KnownTestsCall = APICall<APIDataNoMeta<TestsRequest>, APIDataNoMeta<TestsResponse>>

    var endpoint: Endpoint
    var headers: [HTTPHeader]
    var encoder: JSONEncoder
    var decoder: JSONDecoder
    let httpClient: any HTTPClientType
    let log: Logger

    init(config: APIServiceConfig, httpClient: any HTTPClientType, log: Logger) {
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
               page: KnownTestsPageCursor,
               observer: RequestObserver?) async throws(APICallError) -> KnownTestsResult
    {
        var configurations: [String: JSONGeneric] = configurations.mapValues { .string($0) }
        configurations["custom"] = JSONGeneric(customConfigurations)

        let request = TestsRequest(repositoryUrl: repositoryURL, env: env,
                                   service: service, configurations: configurations,
                                   pageInfo: page)
        let log = self.log
        log.debug("Known tests request: \(request)")
        let response = try await httpClient.call(KnownTestsCall.self,
                                                 url: endpoint.knownTestsURL,
                                                 data: .init(attributes: request),
                                                 headers: headers + [.contentTypeHeader(contentType: .applicationJSON)],
                                                 coders: (encoder, decoder),
                                                 observer: observer)
        log.debug("Known tests response: \(response.data.attributes)")
        let attrs = response.data.attributes
        return KnownTestsResult(tests: attrs.tests, pageInfo: attrs.pageInfo)
    }

    var endpointURLs: Set<URL> { [endpoint.knownTestsURL] }
}

extension KnownTestsApiService {
    struct TestsRequest: Encodable, APIAttributesUUID, CustomDebugStringConvertible {
        let repositoryUrl: String
        let env: String
        let service: String
        let configurations: [String: JSONGeneric]
        let pageInfo: KnownTestsPageCursor

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
        let pageInfo: KnownTestsPageInfo

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
