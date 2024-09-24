/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public struct SpanMetadata {
    private var meta: [String: [String: Value]]
    
    public subscript(bool key: String) -> Bool? {
        get { self[bool: .generic, key] }
        set { self[bool: .generic, key] = newValue }
    }
    
    public subscript(string key: String) -> String? {
        get { self[string: .generic, key] }
        set { self[string: .generic, key] = newValue }
    }
    
    public subscript(bool type: SpanType, key: String) -> Bool? {
        get { self[type, key]?.bool }
        set { self[type, key] = newValue.map { .bool($0) } }
    }
    
    public subscript(string type: SpanType, key: String) -> String? {
        get { self[type, key]?.string }
        set { self[type, key] = newValue.map { .string($0) } }
    }
    
    public subscript(type: SpanType, key: String) -> Value? {
        get { meta[type.rawValue]?[key] }
        set {
            var tStorage = meta[type.rawValue] ?? [:]
            tStorage[key] = newValue
            meta[type.rawValue] = tStorage
        }
    }
    
    public init() {
        self.meta = [:]
    }
    
    public var metadata: [String: [String: Value]] {
        meta.compactMapValues {
            let mapped = $0.compactMapValues { $0.forMetadata }
            return mapped.count > 0 ? mapped : nil
        }
    }
}

public extension SpanMetadata {
    struct SpanType: RawRepresentable, Encodable, Hashable, ExpressibleByStringLiteral {
        public typealias StringLiteralType = String
        public typealias RawValue = String
        
        public let rawValue: String
        
        public init(_ key: String) {
            self.rawValue = key
        }
        
        public init(stringLiteral value: String) {
            self.init(value)
        }
        
        public init?(rawValue: String) {
            self.init(rawValue)
        }
        
        public func encode(to encoder: Encoder) throws {
            try rawValue.encode(to: encoder)
        }
        
        @inlinable public static var generic: SpanType { "*" }
    }
}

public extension SpanMetadata {
    enum Value: Encodable, ExpressibleByNilLiteral, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
        case int(Int)
        case double(Double)
        case string(String)
        case bool(Bool)
        case none(isNumber: Bool)
        
        public typealias StringLiteralType = String
        public typealias IntegerLiteralType = Int
        public typealias FloatLiteralType = Double
        
        public init(nilLiteral: ()) {
            self = .none(isNumber: false)
        }
        
        public init(integerLiteral value: Int) {
            self = .int(value)
        }
        
        public init(floatLiteral value: Double) {
            self = .double(value)
        }
        
        public init(stringLiteral value: String) {
            self = .string(value)
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .none: try container.encodeNil()
            case .int(let i): try container.encode(i)
            case .double(let d): try container.encode(d)
            case .string(let s): try container.encode(s)
            case .bool(let b): try container.encode(b ? "true" : "false")
            }
        }
        
        public var bool: Bool? {
            switch self {
            case .bool(let b): return b
            case .double(let d): return !d.isZero
            case .int(let i): return i != 0
            case .string(let s):
                switch s.lowercased() {
                case "true", "1": return true
                case "false", "0": return false
                default: return nil
                }
            default: return nil
            }
        }
        
        public var int: Int? {
            switch self {
            case .int(let i): return i
            case .double(let d): return Int(exactly: d)
            case .bool(let b): return b ? 1 : 0
            default: return nil
            }
        }
        
        public var double: Double? {
            switch self {
            case .int(let i): return Double(exactly: i)
            case .double(let d): return d
            case .bool(let b): return b ? 1.0 : 0.0
            default: return nil
            }
        }
        
        public var string: String? {
            switch self {
            case .int(let i): return String(i, radix: 10)
            case .double(let d): return String(d)
            case .bool(let b): return b ? "true" : "false"
            case .string(let s): return s
            default: return nil
            }
        }
        
        public var forMetrics: Self? {
            switch self {
            case .double, .int: return self
            case .none(isNumber: let n): return n ? self : nil
            default: return nil
            }
        }
        
        public var forMetadata: Self? {
            switch self {
            case .string, .bool: return self
            case .none(isNumber: let n): return n ? nil : self
            default: return nil
            }
        }
    }
}

// Metrics
public extension SpanMetadata {
    subscript(int key: String) -> Int? {
        get { self[int: .generic, key] }
        set { self[int: .generic, key] = newValue }
    }
    
    subscript(double key: String) -> Double? {
        get { self[double: .generic, key] }
        set { self[double: .generic, key] = newValue }
    }
    
    subscript(int type: SpanType, key: String) -> Int? {
        get { self[type, key]?.int }
        set { self[type, key] = newValue.map { .int($0) } }
    }
    
    subscript(double type: SpanType, key: String) -> Double? {
        get { self[type, key]?.double }
        set { self[type, key] = newValue.map { .double($0) } }
    }
    
    var metrics: [String: [String: Value]] {
        meta.compactMapValues {
            let mapped = $0.compactMapValues { $0.forMetrics }
            return mapped.count > 0 ? mapped : nil
        }
    }
}
