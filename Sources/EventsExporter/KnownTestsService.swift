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

internal final class KnownTestsService {
    let exporterConfiguration: ExporterConfiguration
    let testsUploader: DataUploader
    
    init(config: ExporterConfiguration) throws {
        self.exporterConfiguration = config
        
        let testsRequestBuilder = SingleRequestBuilder(
            url: exporterConfiguration.endpoint.knownTestsURL,
            queryItems: [],
            headers: [
                .userAgentHeader(
                    appName: exporterConfiguration.applicationName,
                    appVersion: exporterConfiguration.version,
                    device: Device.current
                ),
                .contentTypeHeader(contentType: .applicationJSON),
                .apiKeyHeader(apiKey: config.apiKey),
                .traceIDHeader(traceID: config.exporterId),
                .parentSpanIDHeader(parentSpanID: config.exporterId),
                .samplingPriorityHeader()
            ]
        )
        
        testsUploader = DataUploader(
            httpClient: HTTPClient(debug: config.debug.logNetworkRequests),
            requestBuilder: testsRequestBuilder
        )
    }
    
    /// Fetches known tests, with optional pagination. When `pageInfo` is nil,
    /// all pages are fetched and merged; otherwise a single page is returned with `pageInfo` for iteration.
    func tests(
        service: String, env: String, repositoryURL: String,
        configurations: [String: String], customConfigurations: [String: String],
        pageInfo: KnownTestsPageInfo? = nil
    ) -> KnownTestsResult? {
        var configurations: [String: JSONGeneric] = configurations.mapValues { .string($0) }
        configurations["custom"] = .stringDict(customConfigurations)
        
        let onePageOnly: Bool = (pageInfo != nil)
        var tests: KnownTestsMap = [:]
        var pageInfo: KnownTestsPageInfo = pageInfo ?? .init()
        var size: Int = 0
        repeat {
            guard let result = fetchPage(
                service: service, env: env, repositoryURL: repositoryURL,
                configurations: configurations,
                pageInfo: pageInfo.requestParameters
            ) else {
                return nil
            }
            tests = tests.merging(result.tests) { (current, new) in
                current.merging(new) { (current, new) in
                    Array(Set(current).union(new))
                }
            }
            pageInfo = result.pageInfo
            size += result.pageInfo.size
        } while !onePageOnly && pageInfo.hasNext

        return KnownTestsResult(tests: tests,
                                pageInfo: .init(cursor: pageInfo.cursor,
                                                pageSize: pageInfo.pageSize,
                                                size: size,
                                                hasNext: pageInfo.hasNext))
    }

    /// Fetches a single page
    private func fetchPage(
        service: String, env: String, repositoryURL: String,
        configurations: [String: JSONGeneric],
        pageInfo: PageInfoRequest
    ) -> KnownTestsResult? {
        let testsPayload = TestsRequest(
            service: service, env: env, repositoryURL: repositoryURL,
            configurations: configurations,
            pageInfo: pageInfo
        )

        guard let jsonData = testsPayload.jsonData,
              let response = testsUploader.uploadWithResponse(data: jsonData)
        else {
            Log.debug("Known Tests Request payload: \(testsPayload.jsonString)")
            Log.debug("Known Tests Request no response")
            return nil
        }

        guard let known = try? JSONDecoder().decode(TestsResponse.self, from: response) else {
            Log.debug("EFD Tests Request invalid response: \(String(decoding: response, as: UTF8.self))")
            return nil
        }
        Log.debug("EFD Tests Request response: \(String(decoding: response, as: UTF8.self))")

        let attrs = known.data.attributes
        return KnownTestsResult(tests: attrs.tests,
                                pageInfo: .init(cursor: attrs.pageInfo.cursor,
                                                pageSize: pageInfo.pageSize,
                                                size: attrs.pageInfo.size,
                                                hasNext: attrs.pageInfo.hasNext))
    }
}

extension KnownTestsService {
    /// Pagination parameters for the Known Tests API request.
    struct PageInfoRequest: Codable {
        /// The number of tests to return per page (default/max 2000).
        let pageSize: Int
        /// A reference token for the next page. If omitted or empty, the first page will be returned.
        let pageState: String?

        enum CodingKeys: String, CodingKey {
            case pageSize = "page_size"
            case pageState = "page_state"
        }
    }

    /// Pagination metadata returned by the Known Tests API response.
    struct PageInfoResponse: Codable {
        /// A reference token for the next page. Only present if another page exists.
        let cursor: String?
        /// The number of items contained in the current page.
        let size: Int
        /// Whether there is another page available.
        let hasNext: Bool

        enum CodingKeys: String, CodingKey {
            case cursor
            case size
            case hasNext = "has_next"
        }
    }

    struct TestsRequest: Codable, JSONable {
        let data: Data

        struct Data: Codable {
            var id = "1"
            var type = "ci_app_libraries_tests_request"
            let attributes: Attributes

            struct Attributes: Codable {
                let repositoryURL: String
                let env: String
                let service: String
                let configurations: [String: JSONGeneric]
                let pageInfo: PageInfoRequest

                enum CodingKeys: String, CodingKey {
                    case service
                    case env
                    case repositoryURL = "repository_url"
                    case configurations
                    case pageInfo = "page_info"
                }
            }
        }

        init(
            service: String, env: String, repositoryURL: String,
            configurations: [String: JSONGeneric],
            pageInfo: PageInfoRequest
        ) {
            self.data = Data(
                attributes: Data.Attributes(
                    repositoryURL: repositoryURL, env: env, service: service,
                    configurations: configurations,
                    pageInfo: pageInfo
                )
            )
        }
    }

    struct TestsResponse: Codable {
        let data: Data

        struct Data: Codable {
            var id = "1"
            var type = "ci_app_libraries_tests"
            let attributes: Attributes

            struct Attributes: Codable {
                let tests: KnownTestsMap
                let pageInfo: PageInfoResponse

                enum CodingKeys: String, CodingKey {
                    case tests
                    case pageInfo = "page_info"
                }
            }
        }
    }
}

extension KnownTestsPageInfo {
    var requestParameters: KnownTestsService.PageInfoRequest {
        .init(pageSize: pageSize, pageState: cursor)
    }
}
