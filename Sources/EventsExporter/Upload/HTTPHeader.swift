/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

enum ContentType: String {
    case applicationJSON = "application/json"
    case textPlainUTF8 = "text/plain;charset=UTF-8"
    case multipartFormData = "multipart/form-data"
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
