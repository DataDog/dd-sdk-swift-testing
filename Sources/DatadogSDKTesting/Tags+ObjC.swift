/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

@objc public class DDTag: NSObject, SomeTag {
    public typealias Value = Any
    
    public let tag: AnyTag
    public var valueType: Any.Type { tag.valueType }
    
    @objc public var name: String { tag.name }
    @objc public var tagType: TagType { tag.tagType }
    @objc public var valueTypeClass: AnyClass? { tag.valueType as? AnyClass }
    @objc public var valueTypeName: String { String(describing: tag.valueType) }
    
    public init<V>(tag: DynamicTag<V>) {
        self.tag = tag.any
        super.init()
    }
    
    public convenience required init?(any tag: AnyTag) {
        self.init(tag: tag)
    }
    
    @objc public convenience init(name: String, andType ttype: TagType, forClass ctype: AnyClass) {
        self.init(tag: AnyTag(name: name, tagType: ttype, valueType: ctype))
    }
    
    @objc public convenience init(asInt name: String, withType ttype: TagType) {
        self.init(tag: DynamicTag<Int>(name: name, tagType: ttype))
    }
    
    @objc public convenience init(asUInt name: String, withType ttype: TagType) {
        self.init(tag: DynamicTag<UInt>(name: name, tagType: ttype))
    }
    
    @objc public convenience init(asBool name: String, withType ttype: TagType) {
        self.init(tag: DynamicTag<Bool>(name: name, tagType: ttype))
    }
    
    @objc public convenience init(asDouble name: String, withType ttype: TagType) {
        self.init(tag: DynamicTag<Double>(name: name, tagType: ttype))
    }
    
    @objc public convenience init(asString name: String, withType ttype: TagType) {
        self.init(tag: DynamicTag<String>(name: name, tagType: ttype))
    }
    
    @objc public convenience init(asDate name: String, withType ttype: TagType) {
        self.init(tag: DynamicTag<Date>(name: name, tagType: ttype))
    }
    
    @objc public convenience init(asData name: String, withType ttype: TagType) {
        self.init(tag: DynamicTag<Data>(name: name, tagType: ttype))
    }
    
    @objc public convenience init(asArray name: String, withType ttype: TagType) {
        self.init(tag: DynamicTag<[Any]>(name: name, tagType: ttype))
    }
    
    @objc public convenience init(asDictionary name: String, withType ttype: TagType) {
        self.init(tag: DynamicTag<[String: Any]>(name: name, tagType: ttype))
    }
    
    public func tryConvert(value: Any) -> Any? {
        switch ObjectIdentifier(tag.valueType) {
        case ObjectIdentifier(Int.self):  return value as? Int
        case ObjectIdentifier(UInt.self): return value as? UInt
        case ObjectIdentifier(Bool.self): return value as? Bool
        case ObjectIdentifier(Double.self): return value as? Double
        case ObjectIdentifier(String.self): return value as? String
        case ObjectIdentifier(Date.self): return value as? Date
        case ObjectIdentifier(Data.self): return value as? Data
        case ObjectIdentifier([Any].self): return value as? [Any]
        case ObjectIdentifier([String: Any].self): return value as? [String: Any]
        case ObjectIdentifier(type(of: value)): return value
        default: return nil
        }
    }
}

@objc public final class DDAttachedTag: NSObject {
    @objc public let tag: DDTag
    @objc public let to: String
    
    @objc public init(tag: DDTag, to: String) {
        self.tag = tag
        self.to = to
    }
    
    @inlinable
    public convenience init<V>(tag: DynamicTag<V>, to: String) {
        self.init(tag: DDTag(tag: tag), to: to)
    }
    
    @inlinable
    public convenience init<T: SomeTag>(tag: AttachedTag<T>) {
        self.init(tag: tag.tag.any, to: tag.to)
    }
    
    @inlinable
    public var swiftTag: AttachedTag<AnyTag> {
        AttachedTag(tag: tag.tag, to: to)
    }
}

public extension AttachedTag {
    var objcTag: DDAttachedTag { DDAttachedTag(tag: self) }
}

@objc public final class DDTypeTags: NSObject, TypeTags, TypeTagsBase {
    let parent: TypeTags?
    let tags: [AttachedTag<AnyTag>: Any]
    
    public init(parent: TypeTags?, tags: [AttachedTag<AnyTag> : Any]) {
        self.parent = parent
        self.tags = tags
    }
    
    @objc public func tagged(byTag tag: DDTag, withPrefix prefix: String?) -> [DDAttachedTag] {
        tagged(by: tag.tag, prefixed: prefix).map{$0.objcTag}
    }
    
    @objc public func tags(forType type: TagType, withPrefix prefix: String?) -> [DDAttachedTag] {
        tags(for: type, prefixed: prefix).map{$0.objcTag}
    }
    
    @objc public func value(forTag tag: DDAttachedTag) -> Any? {
        self[tag.swiftTag]
    }
}

@objc public protocol DDTaggedType: NSObjectProtocol {
    @objc static func associatedTypeTags() -> DDTypeTags
}

@objc public final class DDTypeTagger: NSObject {
    public private(set) var tagger: TypeTagger<NSObject>
    
    private init<T: DDTaggedType & MaybeTaggedType>(for type: T.Type) {
        self.tagger = TypeTagger<NSObject>(type: T.self)
        super.init()
    }
    
    @discardableResult
    @objc public func set(tag: DDTag, toValue value: Any, forMember name: String) -> Bool {
        guard let converted = tag.tryConvert(value: value) else {
            return false
        }
        return tagger.set(any: tag.tag, to: converted, for: name)
    }
    
    @discardableResult
    @objc public func set(typeTag tag: DDTag, toValue value: Any) -> Bool {
        guard tag.tagType == .forType else { return false }
        guard let converted = tag.tryConvert(value: value) else {
            return false
        }
        return tagger.set(anyType: tag.tag, to: value)
    }
    
    @discardableResult
    @objc public func set(tag: DDTag, toValue value: Any, forMethod method: Selector) -> Bool {
        guard tag.tagType == .instanceMethod || tag.tagType == .staticMethod else {
            return false
        }
        return set(tag: tag, toValue: value, forMember: method.description)
    }
    
    @objc public static func forType(_ type: AnyClass) -> DDTypeTagger? {
        (type as? (DDTaggedType & MaybeTaggedType).Type).map { Self(for: $0) }
    }
    
    @objc public func tags() -> DDTypeTags { tagger.tags() }
}

public extension TypeTagger where T: NSObject {
    func tags() -> DDTypeTags {
        DDTypeTags(parent: parentTags, tags: typeTags)
    }
}

// All NSObjects are MaybeTagged.
// We don't have default implementations for protocols in ObjC
extension NSObject: MaybeTaggedType {
    public static var maybeTypeTags: TypeTags? {
        switch self {
        case let tagged as TaggedType.Type: return tagged.dynamicTypeTags
        case let tagged as DDTaggedType.Type: return tagged.associatedTypeTags()
        default: return nil
        }
    }
}
