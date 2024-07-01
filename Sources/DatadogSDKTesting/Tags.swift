/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

@objc public enum TagType: Int, Hashable, Equatable, CustomDebugStringConvertible {
    case forType
    case staticMethod
    case staticProperty
    case instanceMethod
    case instanceProperty
    
    public var debugDescription: String {
        switch self {
        case .forType: return "TypeTag"
        case .instanceMethod: return "InstanceMethodTag"
        case .instanceProperty: return "InstancePropertyTag"
        case .staticMethod: return "StaticMethodTag"
        case .staticProperty: return "StaticPropertyTag"
        }
    }
}

public protocol SomeTag<Value>: Hashable, Equatable, CustomDebugStringConvertible {
    associatedtype Value
    
    var tagType: TagType { get }
    var name: String { get }
    var valueType: Any.Type { get }
    
    init?(any tag: AnyTag)
}

public extension SomeTag {
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
        name == tag.name && tagType == tag.tagType &&
            ObjectIdentifier(valueType) == ObjectIdentifier(tag.valueType)
    }
    
    var debugDescription: String { "\(tagType)<\(valueType)>.\(name)" }
}

public protocol StaticTag<ForType>: SomeTag, ExpressibleByStringLiteral
    where StringLiteralType == String
{
    associatedtype ForType: TaggedType
    init(name: String)
    static var tagType: TagType { get }
}

public extension StaticTag {
    @inlinable
    var valueType: Any.Type { Value.self }
    
    @inlinable
    var tagType: TagType { Self.tagType }
    
    @inlinable
    init?(any tag: AnyTag) {
        guard tag.tagType == Self.tagType && tag.valueType == Value.self else {
            return nil
        }
        self.init(name: tag.name)
    }
    
    @inlinable
    init(stringLiteral: String) {
        self.init(name: stringLiteral)
    }
}

public typealias AnyTag = DynamicTag<Any>

public struct DynamicTag<V>: SomeTag {
    public typealias Value = V
    
    public let name: String
    public let tagType: TagType
    public let valueType: Any.Type
    
    public init(name: String, tagType: TagType) {
        self.name = name
        self.tagType = tagType
        self.valueType = V.self
    }
    
    public init?(any tag: AnyTag) {
        guard Value.self == Any.self || tag.valueType == Value.self else {
            return nil
        }
        self.name = tag.name
        self.tagType = tag.tagType
        self.valueType = tag.valueType
    }
}

public extension DynamicTag where V == Any {
    init<T: SomeTag>(tag: T) {
        self.name = tag.name
        self.tagType = tag.tagType
        self.valueType = tag.valueType
    }
    
    init(name: String, tagType: TagType, valueType: Any.Type) {
        self.name = name
        self.valueType = valueType
        self.tagType = tagType
    }
}

public struct InstancePropertyTag<T: TaggedType, V>: StaticTag {
    public typealias ForType = T
    public typealias Value = V
    
    public let name: String
    
    public init(name: String) {
        self.name = name
    }
    
    public static var tagType: TagType { .instanceProperty }
}

public struct StaticPropertyTag<T: TaggedType, V>: StaticTag {
    public typealias ForType = T
    public typealias Value = V
    
    public let name: String
    
    public init(name: String) {
        self.name = name
    }
    
    public static var tagType: TagType { .staticProperty }
}

public struct InstanceMethodTag<T: TaggedType, V>: StaticTag {
    public typealias ForType = T
    public typealias Value = V
    
    public let name: String
    
    public init(name: String) {
        self.name = name
    }
    
    public static var tagType: TagType { .instanceMethod }
}

public struct StaticMethodTag<T: TaggedType, V>: StaticTag {
    public typealias ForType = T
    public typealias Value = V
    
    public let name: String
    
    public init(name: String) {
        self.name = name
    }
    
    public static var tagType: TagType { .staticMethod }
}

public struct TypeTag<T: TaggedType, V>: StaticTag {
    public typealias ForType = T
    public typealias Value = V
    
    public let name: String
    
    public init(name: String) {
        self.name = name
    }
    
    public static var tagType: TagType { .forType }
}

public struct AttachedTag<Tg: SomeTag>: Hashable, Equatable, CustomDebugStringConvertible {
    public let tag: Tg
    public let to: String
    
    public init(tag: Tg, to member: String) {
        self.tag = tag
        self.to = member
    }
    
    @inlinable
    public init?(type tag: Tg) {
        guard tag.tagType == .forType else { return nil }
        self.init(tag: tag, to: "@")
    }
    
    public init?<T>(tag: Tg, to property: PartialKeyPath<T>) {
        guard tag.tagType == .instanceProperty else { return nil }
        var name = String(describing: property)
        if name.hasPrefix("\\"), let index = name.firstIndex(of: ".") {
            name = String(name[name.index(after: index)...])
        }
        self.init(tag: tag, to: name)
    }
    
    @inlinable
    public init?(tag: Tg, to method: Selector) {
        guard tag.tagType == .staticMethod || tag.tagType == .instanceMethod else { return nil }
        self.init(tag: tag, to: method.description)
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
    
    public var debugDescription: String { "\(tag)[\"\(to)\"]" }
    
    @inlinable
    public func eq<Tg2: SomeTag>(to other: AttachedTag<Tg2>) -> Bool {
        tag.eq(to: other.tag) && to == other.to
    }
    
    @inlinable
    public static func to<T: TaggedType, V>(type tag: TypeTag<T, V>) -> AttachedTag<TypeTag<T, V>> {
        AttachedTag<_>(type: tag)!
    }
    
    @inlinable
    public static func to<V>(typeDynamic tag: DynamicTag<V>) -> AttachedTag<DynamicTag<V>>? {
        AttachedTag<_>(type: tag)
    }
    
    @inlinable
    public static func to<T: TaggedType, V>(method named: String, static tag: StaticMethodTag<T, V>) -> AttachedTag<StaticMethodTag<T, V>> {
        AttachedTag<_>(tag: tag, to: named)
    }
    
    @inlinable
    public static func to<T: TaggedType, V>(method named: String, instance tag: InstanceMethodTag<T, V>) -> AttachedTag<InstanceMethodTag<T, V>> {
        AttachedTag<_>(tag: tag, to: named)
    }
    
    @inlinable
    public static func to<T: NSObjectProtocol & TaggedType, V>(method selector: Selector, static tag: StaticMethodTag<T, V>) -> AttachedTag<StaticMethodTag<T, V>> {
        AttachedTag<_>(tag: tag, to: selector)!
    }
    
    @inlinable
    public static func to<T: NSObjectProtocol & TaggedType, V>(method selector: Selector, instance tag: InstanceMethodTag<T, V>) -> AttachedTag<InstanceMethodTag<T, V>> {
        AttachedTag<_>(tag: tag, to: selector)!
    }
    
    @inlinable
    public static func to<V>(method named: String, dynamic tag: DynamicTag<V>) -> AttachedTag<DynamicTag<V>>? {
        guard tag.tagType == .instanceMethod || tag.tagType == .staticMethod else { return nil }
        return AttachedTag<_>(tag: tag, to: named)
    }
    
    @inlinable
    public static func to<V>(method selector: Selector, dynamic tag: DynamicTag<V>) -> AttachedTag<DynamicTag<V>>? {
       AttachedTag<_>(tag: tag, to: selector)
    }
    
    @inlinable
    public static func to<T: TaggedType, V>(property named: String, static tag: StaticPropertyTag<T, V>) -> AttachedTag<StaticPropertyTag<T, V>> {
        AttachedTag<_>(tag: tag, to: named)
    }
    
    @inlinable
    public static func to<T: TaggedType, V>(property named: String, instance tag: InstancePropertyTag<T, V>) -> AttachedTag<InstancePropertyTag<T, V>> {
        AttachedTag<_>(tag: tag, to: named)
    }
    
    @inlinable
    public static func to<T: TaggedType, V>(property path: PartialKeyPath<T>, instance tag: InstancePropertyTag<T, V>) -> AttachedTag<InstancePropertyTag<T, V>> {
        AttachedTag<_>(tag: tag, to: path)!
    }
    
    @inlinable
    public static func to<V>(property named: String, dynamic tag: DynamicTag<V>) -> AttachedTag<DynamicTag<V>>? {
        guard tag.tagType == .instanceProperty || tag.tagType == .staticProperty else { return nil }
        return AttachedTag<_>(tag: tag, to: named)
    }
    
    @inlinable
    public static func to<T, V>(property path: PartialKeyPath<T>, dynamic tag: DynamicTag<V>) -> AttachedTag<DynamicTag<V>>? {
        AttachedTag<_>(tag: tag, to: path)
    }
}

extension AttachedTag where Tg == AnyTag {
    public func cast<T2: SomeTag>(to other: T2.Type) -> AttachedTag<T2>? {
        T2(any: tag).map { AttachedTag<_>(tag: $0, to: to) }
    }
}

public protocol TypeTags {
    var allTags: [AttachedTag<AnyTag>: Any] { get }
    func tagged<T: SomeTag>(by tag: T, prefixed prefix: String?) -> [AttachedTag<T>]
    func tags(for type: TagType, prefixed prefix: String?) -> [AttachedTag<AnyTag>]
    func tags(named name: String, prefixed prefix: String?) -> [AttachedTag<AnyTag>]
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
    @inlinable
    func tags(named name: String) -> [AttachedTag<AnyTag>] {
        tags(named: name, prefixed: nil)
    }
    @inlinable
    func tagged<V>(dynamic tag: DynamicTag<V>, prefixed prefix: String? = nil) -> [AttachedTag<DynamicTag<V>>] {
        tagged(by: tag, prefixed: prefix)
    }
}

public protocol MaybeTaggedType {
    static var maybeTypeTags: TypeTags? { get }
}

public protocol TaggedType: MaybeTaggedType {
    static var typeTags: TypeTags { get }
}

public protocol ExtendableTaggedType: AnyObject, TaggedType {
    static func extendableTypeTags() -> ExtendableTypeTags
}

public protocol FinalTaggedType: TaggedType {
    static var finalTypeTags: FinalTypeTags<Self> { get }
}

extension TypeTags {
    public func tagged<Tg: SomeTag>(by tag: Tg, prefixed prefix: String?) -> [AttachedTag<Tg>] {
        allTags.keys.filter { atag in
            atag.tag.eq(to: tag) && (prefix.map { atag.to.hasPrefix($0) } ?? true)
        }.compactMap { $0.cast(to: Tg.self) }
    }
    
    public func tags(for type: TagType, prefixed prefix: String?) -> [AttachedTag<AnyTag>] {
        allTags.keys.filter { atag in
            atag.tag.tagType == type && (prefix.map { atag.to.hasPrefix($0) } ?? true)
        }
    }
    
    public func tags(named name: String, prefixed prefix: String?) -> [AttachedTag<AnyTag>] {
        allTags.keys.filter { atag in
            atag.tag.name == name && (prefix.map { atag.to.hasPrefix($0) } ?? true)
        }
    }
    
    public subscript<Tg: SomeTag>(tag: AttachedTag<Tg>) -> Tg.Value? {
        if let val = allTags[tag.any] {
            return val as? Tg.Value
        }
        return nil
    }
    
    public var debugDescription: String {
        String(allTags.reduce(into: "") { desc, elem in
            desc.append("\(elem.key) = \(elem.value)\n")
        }.dropLast(1))
    }
}

public struct ExtendableTypeTags: TypeTags, CustomDebugStringConvertible {
    public let allTags: [AttachedTag<AnyTag> : Any]
    
    public init(tags: [AttachedTag<AnyTag>: Any]) {
        self.allTags = tags
    }
}

public struct FinalTypeTags<T: FinalTaggedType>: TypeTags, CustomDebugStringConvertible {
    public let allTags: [AttachedTag<AnyTag> : Any]
    
    public init(tags: [AttachedTag<AnyTag>: Any]) {
        self.allTags = tags
    }
    
    public func tagged<V>(type tag: TypeTag<T, V>, prefixed prefix: String? = nil) -> [AttachedTag<TypeTag<T, V>>] {
        tagged(by: tag, prefixed: prefix)
    }
    
    public func tagged<V>(instance tag: InstanceMethodTag<T, V>, prefixed prefix: String? = nil) -> [AttachedTag<InstanceMethodTag<T, V>>] {
        tagged(by: tag, prefixed: prefix)
    }
    
    public func tagged<V>(instance tag: InstancePropertyTag<T, V>, prefixed prefix: String? = nil) -> [AttachedTag<InstancePropertyTag<T, V>>] {
        tagged(by: tag, prefixed: prefix)
    }
    
    public func tagged<V>(static tag: StaticMethodTag<T, V>, prefixed prefix: String? = nil) -> [AttachedTag<StaticMethodTag<T, V>>] {
        tagged(by: tag, prefixed: prefix)
    }
    
    public func tagged<V>(static tag: StaticPropertyTag<T, V>, prefixed prefix: String? = nil) -> [AttachedTag<StaticPropertyTag<T, V>>] {
        tagged(by: tag, prefixed: prefix)
    }
}

public struct TypeTagger<T: MaybeTaggedType> {
    let dynamicType: MaybeTaggedType.Type
    var typeTags: [AttachedTag<AnyTag>: Any]
    
    init(parent tags: TypeTags?, type: MaybeTaggedType.Type = T.self) {
        self.typeTags = tags?.allTags ?? [:]
        self.dynamicType = type
    }
    
    init(type: MaybeTaggedType.Type = T.self) {
        self.init(parent: (Swift._getSuperclass(type) as? MaybeTaggedType.Type)?.maybeTypeTags,
                  type: type)
    }
    
    public mutating func set<Tg: SomeTag>(tag: AttachedTag<Tg>, to value: Tg.Value) {
        typeTags[tag.any] = value
    }
    
    @inlinable
    public mutating func set(any tag: AnyTag, to value: Any, for member: String) -> Bool {
        guard type(of: value) == tag.valueType, tag.tagType != .forType else { return false }
        set(tag: AttachedTag(tag: tag, to: member), to: value)
        return true
    }
    
    public mutating func set(anyType tag: AnyTag, to value: Any) -> Bool {
        guard type(of: value) == tag.valueType,
              let atag = AttachedTag<AnyTag>.to(typeDynamic: tag) else
        {
            return false
        }
        set(tag: atag, to: value)
        return true
    }
    
    @inlinable
    public mutating func set<V>(instance tag: InstancePropertyTag<T, V>, to value: V, property path: PartialKeyPath<T>) {
        set(tag: .to(property: path, instance: tag), to: value)
    }
    
    @inlinable
    public mutating func set<V>(instance tag: InstancePropertyTag<T, V>, to value: V, property name: String) {
        set(tag: .to(property: name, instance: tag), to: value)
    }
    
    @inlinable
    public mutating func set<V>(static tag: StaticPropertyTag<T, V>, to value: V, property name: String) {
        set(tag: .to(property: name, static: tag), to: value)
    }
    
    @inlinable
    public mutating func set<V>(instance tag: InstanceMethodTag<T, V>, to value: V, method name: String) {
        set(tag: .to(method: name, instance: tag), to: value)
    }
    
    @inlinable
    public mutating func set<V>(static tag: StaticMethodTag<T, V>, to value: V, method name: String) {
        set(tag: .to(method: name, static: tag), to: value)
    }
    
    @inlinable
    public mutating func set<V>(type tag: TypeTag<T, V>, to value: V) {
        set(tag: .to(type: tag), to: value)
    }
}

public extension TypeTagger where T: ExtendableTaggedType {
    func tags() -> ExtendableTypeTags { ExtendableTypeTags(tags: typeTags) }
}

public extension TypeTagger where T: FinalTaggedType {
    func tags() -> FinalTypeTags<T> { FinalTypeTags(tags: typeTags) }
}

public extension TypeTagger where T: NSObjectProtocol {
    @inlinable
    mutating func set<V>(instance tag: InstanceMethodTag<T, V>, to value: V, method sel: Selector) {
        set(tag: .to(method: sel, instance: tag), to: value)
    }
    @inlinable
    mutating func set<V>(static tag: StaticMethodTag<T, V>, to value: V, method sel: Selector) {
        set(tag: .to(method: sel, static: tag), to: value)
    }
}

public extension ExtendableTaggedType {
    static func withTagger(_ builder: (inout TypeTagger<Self>) -> Void) -> ExtendableTypeTags {
        var tagger = TypeTagger<Self>()
        builder(&tagger)
        return tagger.tags()
    }
}

public extension FinalTaggedType {
    fileprivate static var _erasedTypeTags: TypeTags { finalTypeTags }

    static func withTagger(_ builder: (inout TypeTagger<Self>) -> Void) -> FinalTypeTags<Self> {
        var tagger = TypeTagger<Self>()
        builder(&tagger)
        return tagger.tags()
    }
}

public extension TaggedType {
    @inlinable
    static var typeTags: TypeTags {
        guard let tags = dynamicTypeTags else {
            preconditionFailure("Unknown tagged type protocol: \(String(describing: self))")
        }
        return tags
    }
    
    @inlinable static var maybeTypeTags: TypeTags? { dynamicTypeTags }
    
    // We can have inheritance case ExtendableTaggedType -> FinalTaggedType so we do dynamic check
    static var dynamicTypeTags: TypeTags? {
        switch self {
        case let strong as any FinalTaggedType.Type: return strong._erasedTypeTags
        case let ext as ExtendableTaggedType.Type: return ext.extendableTypeTags()
        default: return nil
        }
    }
}
