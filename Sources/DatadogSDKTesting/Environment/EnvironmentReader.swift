/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal protocol EnvironmentValue {
    init?(configValue: String)
}

internal protocol EnvironmentReader {
    func has(env key: String) -> Bool
    func has(info key: String) -> Bool
    func get<V: EnvironmentValue>(env key: String) -> V?
    func get<V: EnvironmentValue>(info key: String) -> V?
    func reduce<V>(env initial: V, prefix: String?,
                   reducer: (inout V, String, EnvironmentReader) throws -> Void) rethrows -> V
    func reduce<V>(info initial: V, prefix: String?,
                   reducer: (inout V, String, EnvironmentReader) throws -> Void) rethrows -> V
}

internal struct ProcessEnvironmentReader: EnvironmentReader {
    let environment: [String: String]
    let infoDictionary: [String: Any]
    
    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         infoDictionary: [String: Any] = Self.currentBundleInfoDictionary)
    {
        self.environment = environment
        self.infoDictionary = infoDictionary
    }
    
    @inlinable
    static var currentBundleInfoDictionary: [String: Any] {
        Bundle.testBundle?.infoDictionary ?? Bundle.main.infoDictionary ?? [:]
    }
    
    @inlinable
    func has(env key: String) -> Bool {
        environment[key] != nil
    }
    
    @inlinable
    func has(info key: String) -> Bool {
        infoDictionary[key] != nil
    }
    
    func get<V: EnvironmentValue>(env key: String) -> V? {
        guard let envVar = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return envVar.isEmpty ? nil : V(configValue: envVar)
    }
    
    func get<V: EnvironmentValue>(info key: String) -> V? {
        guard let value = infoDictionary[key] else {
            return nil
        }
        if let direct = value as? V {
            return direct
        } else {
            let trimmed = "\(value)".trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : V(configValue: trimmed)
        }
    }
    
    func reduce<V>(env initial: V, prefix: String?,
                   reducer: (inout V, String, EnvironmentReader) throws -> Void) rethrows -> V
    {
        let keys = prefix == nil ? Array(environment.keys) : environment.keys.filter {
            $0.hasPrefix(prefix!)
        }
        return try keys.reduce(into: initial) { res, key in
            try reducer(&res, key, self)
        }
    }
    
    func reduce<V>(info initial: V, prefix: String?,
                   reducer: (inout V, String, EnvironmentReader) throws -> Void) rethrows -> V
    {
        let keys = prefix == nil ? Array(infoDictionary.keys) : infoDictionary.keys.filter {
            $0.hasPrefix(prefix!)
        }
        return try keys.reduce(into: initial) { res, key in
            try reducer(&res, key, self)
        }
    }
}

internal extension EnvironmentReader {
    @inlinable
    func has(_ key: String) -> Bool {
        has(env: key) || has(info: key)
    }
    
    @inlinable
    func get<V: EnvironmentValue>(_ key: String, _ type: V.Type = V.self) -> V? {
        get(env: key) ?? get(info: key)
    }
    
    @inlinable
    func get<V: EnvironmentValue>(env key: String, _ type: V.Type) -> V? {
        get(env: key)
    }
    
    @inlinable
    func get<V: EnvironmentValue>(info key: String, _ type: V.Type) -> V? {
        get(info: key)
    }
    
    @inlinable
    func reduce<V>(env initial: V,
                   reducer: (inout V, String, EnvironmentReader) throws -> Void) rethrows -> V
    {
        try reduce(env: initial, prefix: nil, reducer: reducer)
    }
    
    @inlinable
    func reduce<V>(info initial: V,
                   reducer: (inout V, String, EnvironmentReader) throws -> Void) rethrows -> V
    {
        try reduce(info: initial, prefix: nil, reducer: reducer)
    }
    
    @inlinable
    subscript<V: EnvironmentValue>(key: String, type: V.Type = V.self) -> V? { return get(key) }
}

extension String: EnvironmentValue {
    init?(configValue: String) {
        self = configValue
    }
}

extension Int: EnvironmentValue {
    init?(configValue: String) {
        guard let val = Int(configValue, radix: 10) else {
            return nil
        }
        self = val
    }
}

extension Bool: EnvironmentValue {
    init?(configValue: String) {
        switch configValue.lowercased() {
        case "1", "true", "yes", "t", "y": self = true
        case "0", "false", "no", "f", "n": self = false
        default: return nil
        }
    }
}

extension URL: EnvironmentValue {
    init?(configValue: String) {
        guard let url = URL(string: configValue) else {
            return nil
        }
        self = url
    }
}

extension Date: EnvironmentValue {
    init?(configValue: String) {
        guard let date = ISO8601DateFormatter().date(from: configValue) else {
            return nil
        }
        self = date
    }
}

extension Array: EnvironmentValue where Element: EnvironmentValue {
    init?(configValue: String) {
        let elems = configValue.components(separatedBy: CharacterSet(charactersIn: ",; "))
        let parsed = elems.compactMap { Element(configValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard elems.count == parsed.count else { return nil }
        self = parsed
    }
}

extension Set: EnvironmentValue where Element: EnvironmentValue {
    init?(configValue: String) {
        guard let array = Array<Element>(configValue: configValue) else {
            return nil
        }
        self = Set(array)
    }
}

extension Dictionary: EnvironmentValue where Key == String, Value: EnvironmentValue {
    init?(configValue: String) {
        guard let array = Array<String>(configValue: configValue) else {
            return nil
        }
        let pairs: [(String, Value)] = array.compactMap {
            let pair = $0.components(separatedBy: ":")
            guard pair.count == 2 else { return nil }
            let key = pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return Value(configValue: value).map { (key, $0) }
        }
//        guard pairs.count == array.count else {
//            return nil
//        }
        self = Dictionary(pairs) { (_, right) in right }
    }
}


