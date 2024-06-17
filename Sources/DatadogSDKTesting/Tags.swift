//
//  File.swift
//  
//
//  Created by Yehor Popovych on 04/06/2024.
//

import Foundation

@objc public enum TagType: Int, Hashable, Equatable {
    case forType
    case staticMethod
    case staticProperty
    case instanceMethod
    case instanceProperty
}

public protocol SomeTag<Value>: Hashable, Equatable {
    associatedtype Value
    
    var tagType: TagType { get }
    var name: String { get }
    var valueType: Any.Type { get }
    
    init?(any tag: AnyTag)
}

public extension SomeTag {
    var valueType: Any.Type { Value.self }
    
    @inlinable
    var any: AnyTag { AnyTag(tag: self) }
    
    @inlinable
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.eq(to: rhs)
    }
    
    @inlinable
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(tagType)
        hasher.combine(ObjectIdentifier(valueType))
    }
    
    @inlinable
    func eq<V>(to tag: any SomeTag<V>) -> Bool {
        name == tag.name && tagType == tagType &&
            ObjectIdentifier(valueType) == ObjectIdentifier(tag.valueType)
    }
}

public protocol StaticTag: SomeTag {
    init(name: String)
    static var tagType: TagType { get }
}

public extension StaticTag {
    @inlinable
    var tagType: TagType { Self.tagType }
    
    @inlinable
    init?(any tag: AnyTag) {
        guard tag.tagType == Self.tagType && tag.valueType == Value.self else {
            return nil
        }
        self.init(name: tag.name)
    }
}

public struct AnyTag: SomeTag {
    public typealias Value = Any
    
    public let name: String
    public let tagType: TagType
    public let valueType: Any.Type
    
    public init<T: SomeTag>(tag: T) {
        self.name = tag.name
        self.tagType = tag.tagType
        self.valueType = tag.valueType
    }
    
    @inlinable
    public init?(any tag: AnyTag) {
        self = tag
    }
    
    public init(name: String, valueType: Any.Type, tagType: TagType) {
        self.name = name
        self.valueType = valueType
        self.tagType = tagType
    }
}

public struct InstancePropertyTag<T, V>: StaticTag {
    public typealias Value = V
    
    public let name: String
    
    public init(name: String) {
        self.name = name
    }
    
    public static var tagType: TagType { .instanceProperty }
}

public struct StaticPropertyTag<T, V>: StaticTag {
    public typealias Value = V
    
    public let name: String
    
    public init(name: String) {
        self.name = name
    }
    
    public static var tagType: TagType { .staticProperty }
}

public struct InstanceMethodTag<T, V>: StaticTag {
    public typealias Value = V
    
    public let name: String
    
    public init(name: String) {
        self.name = name
    }
    
    public static var tagType: TagType { .instanceMethod }
}

public struct StaticMethodTag<T, V>: StaticTag {
    public typealias Value = V
    
    public let name: String
    
    public init(name: String) {
        self.name = name
    }
    
    public static var tagType: TagType { .staticMethod }
}

public struct TypeTag<T, V>: StaticTag {
    public typealias Value = V
    
    public let name: String
    
    public init(name: String) {
        self.name = name
    }
    
    public static var tagType: TagType { .forType }
}

public struct AttachedTag<Tg: SomeTag>: Hashable, Equatable {
    public let tag: Tg
    public let to: String
    
    public init(tag: Tg, to: String) {
        self.tag = tag
        self.to = to
    }
    
    @inlinable
    public var any: AttachedTag<AnyTag> {
        AttachedTag<AnyTag>(tag: tag.any, to: to)
    }
    
    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.eq(to: rhs)
    }
    
    @inlinable
    public func hash(into hasher: inout Hasher) {
        tag.hash(into: &hasher)
        hasher.combine(to)
    }
    
    @inlinable
    public func eq<Tg2: SomeTag>(to other: AttachedTag<Tg2>) -> Bool {
        tag.eq(to: other.tag) && to == to
    }
}

extension AttachedTag where Tg == AnyTag {
    public func cast<T2: SomeTag>(to other: T2.Type) -> AttachedTag<T2>? {
        T2(any: tag).map { AttachedTag<_>(tag: $0, to: to) }
    }
}

public protocol TypeTags {
    func tagged<T: SomeTag>(by tag: T, prefixed prefix: String?) -> [AttachedTag<T>]
    func tags(for type: TagType, prefixed prefix: String?) -> [AttachedTag<AnyTag>]
    subscript<T: SomeTag>(_ tag: AttachedTag<T>) -> T.Value? { get }
}

public extension TypeTags {
    @inlinable
    func tagged<T: SomeTag>(by tag: T) -> [AttachedTag<T>] {
        tagged(by: tag, prefixed: nil)
    }
    @inlinable
    func tags(for type: TagType) -> [AttachedTag<AnyTag>] {
        tags(for: type, prefixed: nil)
    }
}

public protocol TaggedType {
    static var typeTags: any TypeTags { get }
}

public protocol FinalTaggedType: TaggedType {
    static var finalTypeTags: FinalTypeTags<Self> { get }
}

public struct FinalTypeTags<T: TaggedType>: TypeTags {
    private let parent: (any TypeTags)?
    private let tags: [AttachedTag<AnyTag>: Any]
    
    public init(parent: (any TypeTags)?, tags: [AttachedTag<AnyTag>: Any]) {
        self.parent = parent
        self.tags = tags
    }
    
    public func tagged<Tg: SomeTag>(by tag: Tg, prefixed prefix: String?) -> [AttachedTag<Tg>] {
        var tags = tags.keys.filter { atag in
            atag.tag.eq(to: tag) && (prefix.map { atag.to.hasPrefix($0) } ?? true)
        }.compactMap { $0.cast(to: Tg.self) }
        if let parent = self.parent {
            tags.append(contentsOf: parent.tagged(by: tag, prefixed: prefix))
        }
        return tags
    }
    
    public func tags(for type: TagType, prefixed prefix: String?) -> [AttachedTag<AnyTag>] {
        var tags = tags.keys.filter { atag in
            atag.tag.tagType == type && (prefix.map { atag.to.hasPrefix($0) } ?? true)
        }
        if let parent = self.parent {
            tags.append(contentsOf: parent.tags(for: type, prefixed: prefix))
        }
        return tags
    }
    
    public subscript<Tg: SomeTag>(tag: AttachedTag<Tg>) -> Tg.Value? {
        if let val = tags[tag.any] {
            return val as? Tg.Value
        }
        return parent?[tag]
    }
}

public struct TypeTagger<T: TaggedType> {
    private let parentTags: TypeTags?
    private var tags: [AttachedTag<AnyTag>: Any]
    
    init(parent tags: TypeTags?) {
        self.parentTags = tags
        self.tags = [:]
    }
    
    init(type: TaggedType.Type = T.self) {
        self.init(parent: (Swift._getSuperclass(type) as? TaggedType.Type)?.anyTypeTags)
    }
    
    public mutating func set<Tg: SomeTag>(value: Tg.Value, some tag: Tg, to name: String) {
        tags[AttachedTag(tag: tag, to: name).any] = value
    }
    
    public mutating func set(value: Any, for tag: AnyTag, to name: String) throws {
        guard type(of: value) == tag.valueType else {
            throw TagValueTypeError(expectedValueType: tag.valueType,
                                    providedValueType: type(of: value))
        }
        set(value: value, some: tag, to: name)
    }
    
    @inlinable
    public mutating func set<V>(value: V, for tag: InstancePropertyTag<T, V>, instance property: PartialKeyPath<T>) {
        set(value: value, some: tag, to: String(describing: property))
    }
    
    @inlinable
    public mutating func set<V>(value: V, for tag: InstancePropertyTag<T, V>, instance property: String) {
        set(value: value, some: tag, to: property)
    }
    
    @inlinable
    public mutating func set<V>(value: V, for tag: StaticPropertyTag<T, V>, static property: String) {
        set(value: value, some: tag, to: property)
    }
    
    @inlinable
    public mutating func set<V>(value: V, for tag: InstanceMethodTag<T, V>, instance method: String) {
        set(value: value, some: tag, to: method)
    }
    
    @inlinable
    public mutating func set<V>(value: V, for tag: StaticMethodTag<T, V>, static method: String) {
        set(value: value, some: tag, to: method)
    }
    
    @inlinable
    public mutating func set<V>(value: V, for tag: TypeTag<T, V>) {
        set(value: value, some: tag, to: String(describing: T.self))
    }
    
    public func build() -> any TypeTags { _build() }
    
    private func _build() -> FinalTypeTags<T> {
        FinalTypeTags(parent: parentTags, tags: tags)
    }
}

public extension TypeTagger where T: FinalTaggedType {
    func buildFinal() -> FinalTypeTags<T> { _build() }
}

public extension TypeTagger where T: NSObjectProtocol {
    @inlinable
    mutating func set<V>(value: V, for tag: InstanceMethodTag<T, V>, instance method: Selector) {
        set(value: value, some: tag, to: method.description)
    }
    @inlinable
    mutating func set<V>(value: V, for tag: StaticMethodTag<T, V>, static method: Selector) {
        set(value: value, some: tag, to: method.description)
    }
}

public extension TaggedType {
    static func withTagger(_ builder: (inout TypeTagger<Self>) -> Void) -> TypeTags {
        var tagger = TypeTagger<Self>()
        builder(&tagger)
        return tagger.build()
    }
}

public extension FinalTaggedType {
    static var typeTags: TypeTags { erasedTypeTags }
    
    static var erasedTypeTags: TypeTags { finalTypeTags }

    static func withTagger(_ builder: (inout TypeTagger<Self>) -> Void) -> FinalTypeTags<Self> {
        var tagger = TypeTagger<Self>()
        builder(&tagger)
        return tagger.buildFinal()
    }
}

public extension TaggedType {
    static var anyTypeTags: TypeTags {
        if let strong = self as? any FinalTaggedType.Type {
            return strong.erasedTypeTags
        }
        return typeTags
    }
}

public struct TagValueTypeError: Error {
    let expectedValueType: Any.Type
    let providedValueType: Any.Type
}
