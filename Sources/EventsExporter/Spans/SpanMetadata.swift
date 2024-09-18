/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public struct SpanMetadata {
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
    
    public enum Number: Encodable {
        case int(Int)
        case double(Double)
        
        public func encode(to encoder: Encoder) throws {
            switch self {
            case .int(let int): try int.encode(to: encoder)
            case .double(let double): try double.encode(to: encoder)
            }
        }
    }
    
    private var meta: [String: [String: EncodableValue]]
    
    public subscript(generic key: String) -> Bool? {
        get { self[.generic, key] }
        set { self[.generic, key] = newValue }
    }
    
    public subscript(generic key: String) -> Int? {
        get { self[.generic, key] }
        set { self[.generic, key] = newValue }
    }
    
    public subscript(generic key: String) -> Double? {
        get { self[.generic, key] }
        set { self[.generic, key] = newValue }
    }
    
    public subscript(generic key: String) -> String? {
        get { self[.generic, key] }
        set { self[.generic, key] = newValue }
    }
    
    public subscript(type: SpanType, key: String) -> Bool? {
        get {
            switch self[any: type, key] {
            case let int as Int: return int == 0 ? false : true
            case let double as Double: return double == 0 ? false : true
            case let bool as Bool: return bool
            case let string as String:
                switch string.lowercased() {
                case "true", "1": return true
                case "false", "0": return false
                default: return nil
                }
            default: return nil
            }
        }
        set { self[any: type, key] = newValue }
    }
    
    public subscript(type: SpanType, key: String) -> Int? {
        get {
            switch self[any: type, key] {
            case let int as Int: return int
            case let double as Double: return Int(exactly: double)
            case let bool as Bool: return bool ? 1 : 0
            default: return nil
            }
        }
        set { self[any: type, key] = newValue }
    }
    
    public subscript(type: SpanType, key: String) -> Double? {
        get {
            switch self[any: type, key] {
            case let double as Double: return double
            case let int as Int: return Double(int)
            case let bool as Bool: return bool ? 1.0 : 0.0
            default: return nil
            }
        }
        set { self[any: type, key] = newValue }
    }
    
    public subscript(type: SpanType, key: String) -> String? {
        get {
            switch self[any: type, key] {
            case let double as Double: return String(double)
            case let int as Int: return String(int)
            case let bool as Bool: return String(bool)
            case let string as String: return string
            default: return nil
            }
        }
        set { self[any: type, key] = newValue }
    }
    
    private subscript(any type: SpanType, key: String) -> (any Encodable)? {
        get { meta[type.rawValue]?[key]?.value }
        set {
            var tStorage = meta[type.rawValue] ?? [:]
            tStorage[key] = newValue.map { EncodableValue($0) }
            meta[type.rawValue] = tStorage
        }
    }
    
    public init() {
        self.meta = [:]
    }
    
    public var metadata: [String: [String: String]] {
        meta.compactMapValues {
            let mapped = $0.compactMapValues { val in
                switch val.value {
                case let string as String: return string
                case let bool as Bool: return bool ? "true" : "false"
                default: return nil
                }
            }
            return mapped.count > 0 ? mapped : nil
        }
    }
    
    public var metrics: [String: [String: Number]] {
        meta.compactMapValues {
            let mapped = $0.compactMapValues { val in
                switch val.value {
                case let int as Int: return Number.int(int)
                case let double as Double: return Number.double(double)
                default: return nil
                }
            }
            return mapped.count > 0 ? mapped : nil
        }
    }
}
