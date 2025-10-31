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
    struct Field: ExpressibleByStringLiteral, CustomStringConvertible, RawRepresentable, Equatable, Hashable {
        typealias StringLiteralType = String
        typealias RawValue = String
        
        var rawValue: String
        var description: String { rawValue }
        
        init(_ value: String) {
            self.rawValue = value.lowercased()
        }
        
        init(stringLiteral value: String) {
            self.init(value)
        }
        
        init?(rawValue: String) {
            self.init(rawValue)
        }
        
        static let contentTypeHeaderField: Self = "Content-Type"
        static let contentEncodingHeaderField: Self = "Content-Encoding"
        static let userAgentHeaderField: Self = "User-Agent"
        static let apiKeyHeaderField: Self = "DD-API-KEY"
        static let applicationKeyHeaderField: Self = "DD-APPLICATION-KEY"
        static let traceIDHeaderField: Self = "X-Datadog-Trace-Id"
        static let parentSpanIDHeaderField: Self = "X-Datadog-Parent-Id"
        static let samplingPriorityHeaderField: Self = "X-Datadog-Sampling-Priority"
        static let hostnameHeaderField: Self = "X-Datadog-Hostname"
        static let retryAfterHeaderField: Self = "Retry-After"
        static let rateLimitResetHeaderField: Self = "X-RateLimit-Reset"
    }

    enum Value: ExpressibleByStringLiteral {
        typealias StringLiteralType = String
        
        /// If the header's value is constant.
        case constant(_ value: String)
        /// If the header's value is different each time.
        case dynamic(_ value: () -> String)
        
        init(stringLiteral value: String) {
            self = .constant(value)
        }
        
        var value: String {
            switch self {
            case .constant(let val): return val
            case .dynamic(let getter): return getter()
            }
        }
    }

    let field: Field
    let value: Value

    // MARK: - Standard Headers

    /// Standard "Content-Type" header.
    static func contentTypeHeader(contentType: ContentType) -> HTTPHeader {
        return HTTPHeader(field: .contentTypeHeaderField, value: .constant(contentType.rawValue))
    }

    /// Standard "User-Agent" header.
    static func userAgentHeader(appName: String, appVersion: String, device: Device) -> HTTPHeader {
        return HTTPHeader(
            field: .userAgentHeaderField,
            value: .constant("\(appName)/\(appVersion) CFNetwork (\(device.model); \(device.osName)/\(device.osVersion))")
        )
    }

    /// Standard "Content-Encoding" header.
    static func contentEncodingHeader(contentEncoding: ContentEncoding) -> HTTPHeader {
        return HTTPHeader(field: .contentEncodingHeaderField, value: .constant(contentEncoding.rawValue))
    }

    // MARK: - Datadog Headers

    /// Datadog request API Key authentication header.
    static func apiKeyHeader(apiKey: String) -> HTTPHeader {
        return HTTPHeader(field: .apiKeyHeaderField, value: .constant(apiKey))
    }

    /// Datadog request Application Key authentication header.
    static func hostnameHeader(hostname: String) -> HTTPHeader {
        return HTTPHeader(field: .hostnameHeaderField, value: .constant(hostname))
    }

    // MARK: - Tracing Headers

    /// Trace ID header.
    static func traceIDHeader(traceID: String) -> HTTPHeader {
        return HTTPHeader(field: .traceIDHeaderField, value: .constant(traceID))
    }

    /// Parent Span ID header.
    static func parentSpanIDHeader(parentSpanID: String) -> HTTPHeader {
        return HTTPHeader(field: .parentSpanIDHeaderField, value: .constant(parentSpanID))
    }

    static func samplingPriorityHeader() -> HTTPHeader {
        return HTTPHeader(field: .samplingPriorityHeaderField, value: .constant("1"))
    }
}

extension URLRequest {
    var httpHeaders: [HTTPHeader] {
        get {
            allHTTPHeaderFields?.compactMap { key, value in
                HTTPHeader(field: .init(key), value: .constant(value))
            } ?? []
        }
        set {
            allHTTPHeaderFields?.removeAll()
            for header in newValue {
                addHTTPHeader(header)
            }
        }
    }
    
    func value(forHTTPHeader field: HTTPHeader.Field) -> String? {
        value(forHTTPHeaderField: field.rawValue)
    }
    
    mutating func setHTTPHeader(_ header: HTTPHeader) {
        setValue(header.value, forHTTPHeader: header.field)
    }
    
    mutating func addHTTPHeader(_ header: HTTPHeader) {
        addValue(header.value, forHTTPHeader: header.field)
    }
    
    mutating func setValue(_ value: HTTPHeader.Value?, forHTTPHeader field: HTTPHeader.Field) {
        setValue(value?.value, forHTTPHeaderField: field.rawValue)
    }
    
    mutating func addValue(_ value: HTTPHeader.Value, forHTTPHeader field: HTTPHeader.Field) {
        addValue(value.value, forHTTPHeaderField: field.rawValue)
    }
}
