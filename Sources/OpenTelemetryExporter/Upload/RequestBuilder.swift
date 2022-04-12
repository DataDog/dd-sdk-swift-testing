/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

/// Builds `URLRequest` for sending data to Datadog.
internal struct RequestBuilder {
    enum QueryItem {
        /// `ddsource={source}` query item
        case ddsource(source: String)
        /// `ddtags={tag1},{tag2},...` query item
        case ddtags(tags: [String])

        var urlQueryItem: URLQueryItem {
            switch self {
            case .ddsource(let source):
                return URLQueryItem(name: "ddsource", value: source)
            case .ddtags(let tags):
                return URLQueryItem(name: "ddtags", value: tags.joined(separator: ","))
            }
        }
    }

    enum ContentType: String {
        case applicationJSON = "application/json"
        case textPlainUTF8 = "text/plain;charset=UTF-8"
    }

    enum ContentEncoding: String {
        case deflate
    }

    struct HTTPHeader {
        static let contentTypeHeaderField = "Content-Type"
        static let contentEncodingHeaderField = "Content-Encoding"
        static let userAgentHeaderField = "User-Agent"
        static let ddAPIKeyHeaderField = "DD-API-KEY"

        enum Value {
            /// If the header's value is constant.
            case constant(_ value: String)
            /// If the header's value is different each time.
            case dynamic(_ value: () -> String)
        }

        let field: String
        let value: Value

        // MARK: - Standard Headers

        /// Standard "Content-Type" header.
        static func contentTypeHeader(contentType: ContentType) -> HTTPHeader {
            return HTTPHeader(field: contentTypeHeaderField, value: .constant(contentType.rawValue))
        }

        /// Standard "User-Agent" header.
        static func userAgentHeader(appName: String, appVersion: String, device: Device) -> HTTPHeader {
            return HTTPHeader(
                field: userAgentHeaderField,
                value: .constant("\(appName)/\(appVersion) CFNetwork (\(device.model); \(device.osName)/\(device.osVersion))")
            )
        }

        /// Standard "Content-Encoding" header.
        static func contentEncodingHeader(contentEncoding: ContentEncoding) -> HTTPHeader {
            return HTTPHeader(field: contentEncodingHeaderField, value: .constant(contentEncoding.rawValue))
        }

        // MARK: - Datadog Headers

        /// Datadog request authentication header.
        static func ddAPIKeyHeader(apiKey: String) -> HTTPHeader {
            return HTTPHeader(field: ddAPIKeyHeaderField, value: .constant(apiKey))
        }
    }

    /// Upload `URL`.
    private let url: URL
    /// Pre-computed HTTP headers (they do not change in succeeding requests).
    private let precomputedHeaders: [String: String]
    /// Computed HTTP headers (their value is different in succeeding requests).
    private let computedHeaders: [String: () -> String]

    // MARK: - Initialization

    init(url: URL, queryItems: [QueryItem], headers: [HTTPHeader]) {
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)

        if !queryItems.isEmpty {
            urlComponents?.queryItems = queryItems.map { $0.urlQueryItem }
        }

        var precomputedHeaders: [String: String] = [:]
        var computedHeaders: [String: () -> String] = [:]
        headers.forEach { header in
            switch header.value {
            case .constant(let value):
                precomputedHeaders[header.field] = value
            case .dynamic(let value):
                computedHeaders[header.field] = value
            }
        }

        self.url = urlComponents?.url ?? url
        self.precomputedHeaders = precomputedHeaders
        self.computedHeaders = computedHeaders
    }

    /// Creates `URLRequest` for uploading given `data` to Datadog.
    /// - Parameter data: data to be uploaded
    /// - Returns: the `URLRequest` object.
    func uploadRequest(with data: Data) -> URLRequest {
        var request = URLRequest(url: url)
        var headers = precomputedHeaders
        computedHeaders.forEach { field, value in headers[field] = value() }

        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.httpBody = headers["Content-Encoding"] != nil ? data.deflated : data
        return request
    }
}
