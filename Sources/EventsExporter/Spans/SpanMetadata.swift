/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public struct SpanMetadata: Encodable {
    public struct SpanType: RawRepresentable, Encodable, Hashable, ExpressibleByStringLiteral {
        public typealias StringLiteralType = String
        public typealias RawValue = String
        
        public let rawValue: String
        
        public init(_ key: String) {
            self.rawValue = key
        }
        
        public init(stringLiteral: String) {
            self.init(stringLiteral)
        }
        
        public init?(rawValue: String) {
            self.init(rawValue)
        }
        
        public func encode(to encoder: Encoder) throws {
            try rawValue.encode(to: encoder)
        }
        
        @inlinable static var generic: SpanType { "*" }
    }
    
    private var meta: [SpanType: [String: EncodableValue]]
    
    public func encode(to encoder: Encoder) throws {
        try meta.encode(to: encoder)
    }
    
    public subscript(generic key: String) -> (any Encodable)? {
        get { self[.generic, key] }
        set { self[.generic, key] = newValue }
    }
    
    public subscript(type: SpanType, key: String) -> (any Encodable)? {
        get { meta[type]?[key]?.value }
        set {
            var tStorage = meta[type] ?? [:]
            tStorage[key] = newValue.map { EncodableValue($0) }
            meta[type] = tStorage
        }
    }
    
    public init() {
        self.meta = [:]
    }
}
