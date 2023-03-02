/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

enum ContentType: String {
    case applicationJSON = "application/json"
    case textPlainUTF8 = "text/plain;charset=UTF-8"
    case multipartFormData = "multipart/form-data"
    case applicationOctetStream = "application/octet-stream"
}

enum ContentEncoding: String {
    case deflate
}

struct HTTPHeader {
    static let contentTypeHeaderField = "Content-Type"
    static let contentEncodingHeaderField = "Content-Encoding"
    static let userAgentHeaderField = "User-Agent"
    static let aPIKeyHeaderField = "DD-API-KEY"
    static let applicationKeyHeaderField = "DD-APPLICATION-KEY"
    static let traceIDHeaderField = "X-Datadog-Trace-Id"
    static let parentSpanIDHeaderField = "X-Datadog-Parent-Id"
    static let samplingPriorityHeaderField = "X-Datadog-Sampling-Priority"
    static let hostnameHeaderField = "X-Datadog-Hostname"

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

    /// Datadog request API Key authentication header.
    static func apiKeyHeader(apiKey: String) -> HTTPHeader {
        return HTTPHeader(field: aPIKeyHeaderField, value: .constant(apiKey))
    }

    /// Datadog request Application Key authentication header.
    static func applicationKeyHeader(applicationKey: String) -> HTTPHeader {
        return HTTPHeader(field: applicationKeyHeaderField, value: .constant(applicationKey))
    }

    /// Datadog request Application Key authentication header.
    static func hostnameHeader(hostname: String) -> HTTPHeader {
        return HTTPHeader(field: hostnameHeaderField, value: .constant(hostname))
    }

    // MARK: - Tracing Headers

    /// Trace ID header.
    static func traceIDHeader(traceID: String) -> HTTPHeader {
        return HTTPHeader(field: traceIDHeaderField, value: .constant(traceID))
    }

    /// Parent Span ID header.
    static func parentSpanIDHeader(parentSpanID: String) -> HTTPHeader {
        return HTTPHeader(field: parentSpanIDHeaderField, value: .constant(parentSpanID))
    }

    static func samplingPriorityHeader() -> HTTPHeader {
        return HTTPHeader(field: samplingPriorityHeaderField, value: .constant("1"))
    }
}
