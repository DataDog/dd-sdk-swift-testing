/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public enum JSONGeneric: Codable, Equatable, Hashable, CustomDebugStringConvertible {
    case `nil`
    case bool(Bool)
    case int(Int64)
    case float(Double)
    case string(String)
    case date(Date)
    case bytes(Data)
    case array(Array<Self>)
    case object(Dictionary<String, Self>)
    
    public init(_ dict: [String: String]) {
        self = .object(dict.mapValues { .string($0) })
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .nil
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int64.self) {
            self = .int(int)
        } else if let float = try? container.decode(Double.self) {
            self = .float(float)
        } else if let date = try? container.decode(Date.self) {
            self = .date(date)
        } else if let data = try? container.decode(Data.self) {
            self = .bytes(data)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([Self].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: Self].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown value type"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .nil: try container.encodeNil()
        case .bool(let bool): try container.encode(bool)
        case .int(let int): try container.encode(int)
        case .float(let num): try container.encode(num)
        case .date(let date): try container.encode(date)
        case .bytes(let data): try container.encode(data)
        case .string(let str): try container.encode(str)
        case .array(let arr): try container.encode(arr)
        case .object(let obj): try container.encode(obj)
        }
    }
    
    public var debugDescription: String {
            switch self {
            case .nil: return "null"
            case .int(let int): return "\(int)"
            case .float(let num): return "\(num)"
            case .bool(let bool): return bool ? "true" : "false"
            case .date(let date): return "\"\(Self.formatter.string(from: date))\""
            case .string(let str): return "\"\(str)\""
            case .bytes(let data): return "\"\(data.base64EncodedString())\""
            case .array(let arr):
                return "[\(arr.map{String(describing: $0)}.joined(separator: ", "))]"
            case .object(let obj):
                return "{\(obj.map{"\"\($0)\": \(String(describing: $1))"}.joined(separator: ", "))}"
            }
        }
    
    public static let formatter: ISO8601DateFormatter = .init()
}

