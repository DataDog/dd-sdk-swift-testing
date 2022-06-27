/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

internal protocol RequestBuilder {
    func uploadRequest(with data: Data) -> URLRequest
}

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

/// Builds `URLRequest` for sending data to Datadog.
internal struct SingleRequestBuilder: RequestBuilder {
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

/// Builds `URLRequest` for sending data to Datadog.
internal struct MultipartRequestBuilder: RequestBuilder {
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
        let request = MultipartFormDataRequest(url: url)
        var headers = precomputedHeaders
        computedHeaders.forEach { field, value in headers[field] = value() }
        request.addDataField(named: "coverage1", data:data, mimeType: ContentType.applicationJSON.rawValue)
        request.addDataField(named: "event", data:#"{"dummy": true}"#.data(using: .utf8)!, mimeType: ContentType.applicationJSON.rawValue)
        var urlRequest = request.asURLRequest()
        urlRequest.allHTTPHeaderFields = headers
        return urlRequest
    }
}
