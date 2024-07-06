/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public protocol DDAnyTagValue {
    static var valueType: AnyClass { get }
    static func convertFromObjC(value: Any) -> Any?
    func convertToObjC() -> Any
}

public protocol DDTagValue: DDAnyTagValue {
    associatedtype ObjC: NSObjectProtocol
    static func fromObjC(value: ObjC) -> Self?
    func toObjC() -> ObjC
}

@objc public class DDTag: NSObject {
    public let tag: AnyTag
    
    @objc public var name: String { tag.name }
    @objc public var tagType: TagType { tag.tagType }
    @objc public var valueType: AnyClass { (tag.valueType as! DDAnyTagValue.Type).valueType }
    
    @inlinable
    public convenience init<V: DDAnyTagValue>(tag: DynamicTag<V>) {
        self.init(some: tag)
    }
    
    public convenience init?(any tag: AnyTag) {
        guard tag.valueType is any DDTagValue.Type else { return nil }
        self.init(tag)
    }
    
    public convenience init<T: SomeTag>(some tag: T) where T.Value: DDAnyTagValue {
        self.init(tag.any)
    }
    
    private init(_ tag: AnyTag) {
        self.tag = tag
        super.init()
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
    
    public func toSwift(value: Any) -> Any? {
        (tag.valueType as! DDAnyTagValue.Type).convertFromObjC(value: value)
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
    public convenience init<V: DDAnyTagValue>(tag: DynamicTag<V>, to: String) {
        self.init(tag: DDTag(tag: tag), to: to)
    }
    
    @inlinable
    public convenience init<T: SomeTag>(tag: AttachedTag<T>) where T.Value: DDAnyTagValue {
        self.init(tag: DDTag(some: tag.tag), to: tag.to)
    }
    
    @inlinable
    public convenience init?(tag: AttachedTag<AnyTag>) {
        guard let ddtag = DDTag(any: tag.tag) else { return nil }
        self.init(tag: ddtag, to: tag.to)
    }
    
    @inlinable
    public var swiftTag: AttachedTag<AnyTag> {
        AttachedTag(tag: tag.tag, to: to)
    }
}

public extension AttachedTag where Tg.Value: DDAnyTagValue {
    var objcTag: DDAttachedTag { DDAttachedTag(tag: self) }
}

public extension AttachedTag where Tg == AnyTag {
    var maybeObjcTag: DDAttachedTag? { DDAttachedTag(tag: self) }
}

@objc public final class DDTypeTags: NSObject, TypeTags {
    public let allTags: [AttachedTag<AnyTag> : Any]
    
    public init(tags: [AttachedTag<AnyTag> : Any]) {
        self.allTags = tags
    }
    
    @objc public func tagged(byTag tag: DDTag, withPrefix prefix: String?) -> [DDAttachedTag] {
        tagged(by: tag.tag, prefixed: prefix).compactMap{$0.maybeObjcTag}
    }
    
    @objc public func tags(forType type: TagType, withPrefix prefix: String?) -> [DDAttachedTag] {
        tags(for: type, prefixed: prefix).compactMap{$0.maybeObjcTag}
    }
    
    @objc public func tags(named name: String, withPrefix prefix: String?) -> [DDAttachedTag] {
        tags(named: name, prefixed: prefix).compactMap{$0.maybeObjcTag}
    }
    
    @objc public func value(forTag tag: DDAttachedTag) -> Any? {
        (self[tag.swiftTag] as? DDAnyTagValue)?.convertToObjC()
    }
}

@objc public protocol DDTaggedType: NSObjectProtocol {
    @objc static func attachedTypeTags() -> DDTypeTags
}

@objc public final class DDTypeTagger: NSObject {
    public private(set) var tagger: TypeTagger<NSObject>
    
    public init<T: DDTaggedType & MaybeTaggedType>(for type: T.Type) {
        self.tagger = TypeTagger<NSObject>(parent: type.parentTaggedType?.maybeTypeTags,
                                           type: type)
        super.init()
    }
    
    @objc public static func forType(_ type: AnyClass) -> DDTypeTagger? {
        (type as? (DDTaggedType & MaybeTaggedType).Type).map { Self(for: $0) }
    }
    
    @discardableResult
    @objc public func set(tag: DDTag, toValue value: Any, forMember name: String) -> Bool {
        guard let converted = tag.toSwift(value: value) else {
            return false
        }
        return tagger.set(any: tag.tag, to: converted, for: name)
    }
    
    @objc public func remove(tag: DDTag, forMember name: String) {
        tagger.remove(any: tag.tag, for: name)
    }
    
    @discardableResult
    @objc public func set(typeTag tag: DDTag, toValue value: Any) -> Bool {
        guard let converted = tag.toSwift(value: value) else {
            return false
        }
        return tagger.set(anyType: tag.tag, to: converted)
    }
    
    @objc public func remove(typeTag tag: DDTag) {
        tagger.remove(anyType: tag.tag)
    }
    
    @discardableResult
    @objc public func set(tag: DDTag, toValue value: Any, forMethod method: Selector) -> Bool {
        guard tag.tagType == .instanceMethod || tag.tagType == .staticMethod else {
            return false
        }
        return set(tag: tag, toValue: value, forMember: method.description)
    }
    
    @objc public func remove(tag: DDTag, forMethod method: Selector) {
        remove(tag: tag, forMember: method.description)
    }
    
    @objc public func tags() -> DDTypeTags { tagger.tags() }
}

public extension TypeTagger where T: NSObject {
    func tags() -> DDTypeTags { DDTypeTags(tags: typeTags) }
}

// All NSObjects are MaybeTagged.
// We don't have default implementations for protocols in ObjC
extension NSObject: MaybeTaggedType {
    public static var maybeTypeTags: TypeTags? {
        switch self {
        case let strong as any FinalTaggedType.Type: return strong._erasedTypeTags
        case let ext as ExtendableTaggedType.Type: return ext.extendableTypeTags()
        case let objc as DDTaggedType.Type: return objc.attachedTypeTags()
        default: return nil
        }
    }
}

extension NSObject: ExtendableDynamicHook {
    // Hook to be called from ExtendableTaggedType
    // This hook exists for handling DDTaggedType -> ExtendableTaggedType situation
    // We call ExtendableTaggedType method, but someone subclassed it with DDTaggedType class
    // So we have to call DDTaggedType method instead, and it will call us after
    public static func fetchDynamicTags(selfType: ExtendableDynamicHook.Type,
                                        implType: ExtendableDynamicHook.Type) -> (any TypeTags)?
    {
        // Check that there are some types on top of extendable implementstion
        // And that subclass implemented DDTaggedType
        guard selfType != implType, let tObjc = selfType as? DDTaggedType.Type else {
            return nil
        }
        let sel = NSSelectorFromString("attachedTypeTags")
        // check that attachedTypeTags is overriden somewhere beetween subclass
        // and last ExtendableTaggedType implementation in the class chain
        if class_getClassMethod(tObjc, sel) != class_getClassMethod(implType, sel) {
            return tObjc.attachedTypeTags()
        }
        return nil
    }
}

public extension DDTagValue {
    static var valueType: AnyClass { ObjC.self }
    static func convertFromObjC(value: Any) -> Any? { fromAnyObjC(value: value) }
    func convertToObjC() -> Any { toObjC() }
    static func fromAnyObjC(value: Any) -> Self? {
        switch value {
        case let slf as Self: return slf
        case let objc as ObjC: return fromObjC(value: objc)
        default: return nil
        }
    }
}
// Values
extension Int8: DDTagValue {
    public typealias ObjC = NSNumber
    public static func fromObjC(value: ObjC) -> Self? { value.int8Value }
    public func toObjC() -> ObjC { NSNumber(value: self) }
}

extension Int16: DDTagValue {
    public typealias ObjC = NSNumber
    public static func fromObjC(value: ObjC) -> Self? { value.int16Value }
    public func toObjC() -> ObjC { NSNumber(value: self) }
}

extension Int32: DDTagValue {
    public typealias ObjC = NSNumber
    public static func fromObjC(value: ObjC) -> Self? { value.int32Value }
    public func toObjC() -> ObjC { NSNumber(value: self) }
}

extension Int64: DDTagValue {
    public typealias ObjC = NSNumber
    public static func fromObjC(value: ObjC) -> Self? { value.int64Value }
    public func toObjC() -> ObjC { NSNumber(value: self) }
}

extension Int: DDTagValue {
    public typealias ObjC = NSNumber
    public static func fromObjC(value: ObjC) -> Self? { value.intValue }
    public func toObjC() -> ObjC { NSNumber(value: self) }
}

extension UInt8: DDTagValue {
    public typealias ObjC = NSNumber
    public static func fromObjC(value: ObjC) -> Self? { value.uint8Value }
    public func toObjC() -> ObjC { NSNumber(value: self) }
}

extension UInt16: DDTagValue {
    public typealias ObjC = NSNumber
    public static func fromObjC(value: ObjC) -> Self? { value.uint16Value }
    public func toObjC() -> ObjC { NSNumber(value: self) }
}

extension UInt32: DDTagValue {
    public typealias ObjC = NSNumber
    public static func fromObjC(value: ObjC) -> Self? { value.uint32Value }
    public func toObjC() -> ObjC { NSNumber(value: self) }
}

extension UInt64: DDTagValue {
    public typealias ObjC = NSNumber
    public static func fromObjC(value: ObjC) -> Self? { value.uint64Value }
    public func toObjC() -> ObjC { NSNumber(value: self) }
}

extension UInt: DDTagValue {
    public typealias ObjC = NSNumber
    public static func fromObjC(value: ObjC) -> Self? { value.uintValue }
    public func toObjC() -> ObjC { NSNumber(value: self) }
}

extension Bool: DDTagValue {
    public typealias ObjC = NSNumber
    public static func fromObjC(value: ObjC) -> Self? { value.boolValue }
    public func toObjC() -> ObjC { NSNumber(value: self) }
}

extension Float: DDTagValue {
    public typealias ObjC = NSNumber
    public static func fromObjC(value: ObjC) -> Self? { value.floatValue }
    public func toObjC() -> ObjC { NSNumber(value: self) }
}

extension Double: DDTagValue {
    public typealias ObjC = NSNumber
    public static func fromObjC(value: ObjC) -> Self? { value.doubleValue }
    public func toObjC() -> ObjC { NSNumber(value: self) }
}

extension Data: DDTagValue {
    public typealias ObjC = NSData
    public static func fromObjC(value: ObjC) -> Self? { value as Data }
    public func toObjC() -> ObjC { self as NSData }
}

extension String: DDTagValue {
    public typealias ObjC = NSString
    public static func fromObjC(value: ObjC) -> Self? { value as String }
    public func toObjC() -> ObjC { self as NSString }
}

extension Date: DDTagValue {
    public typealias ObjC = NSDate
    public static func fromObjC(value: ObjC) -> Self? { value as Date }
    public func toObjC() -> ObjC { self as NSDate }
}

extension Array: DDAnyTagValue where Element: DDAnyTagValue {
    public static var valueType: AnyClass { NSArray.self }
    public static func convertFromObjC(value: Any) -> Any? {
        guard let array = value as? NSArray else { return nil }
        let mapped = array.compactMap { Element.convertFromObjC(value: $0) }
        return mapped.count == array.count ? mapped : nil
    }
    public func convertToObjC() -> Any {
        map { $0.convertToObjC() } as NSArray
    }
}
extension Array: DDTagValue where Element: DDTagValue {
    public typealias ObjC = NSArray
    public static func fromObjC(value: ObjC) -> Self? {
        let mapped = value.compactMap { Element.fromAnyObjC(value: $0) }
        return mapped.count == value.count ? mapped : nil
    }
    public func toObjC() -> ObjC {
        map { $0.toObjC() } as NSArray
    }
}

extension Dictionary: DDAnyTagValue where Key: DDTagValue, Value: DDAnyTagValue, Key.ObjC: NSCopying {
    public static var valueType: AnyClass { NSDictionary.self }
    
    public static func convertFromObjC(value: Any) -> Any? {
        guard let dict = value as? NSDictionary else { return nil }
        let mapped = dict.compactMap { (key, value) in
            Key.fromAnyObjC(value: key).flatMap { key in
                Value.convertFromObjC(value: value).map { (key, $0) }
            }
        }
        return mapped.count == dict.count ? Dictionary<_,_>(uniqueKeysWithValues: mapped) : nil
    }
    
    public func convertToObjC() -> Any {
        let out = NSMutableDictionary(capacity: count)
        for (key, val) in self {
            out.setObject(val.convertToObjC(), forKey: key.toObjC())
        }
        return out
    }
}

extension Dictionary: DDTagValue where Key: DDTagValue, Value: DDTagValue, Key.ObjC: NSCopying {
    public typealias ObjC = NSDictionary
    
    public static func fromObjC(value: ObjC) -> Self? {
        let mapped = value.compactMap { (key, value) in
            Key.fromAnyObjC(value: key).flatMap { key in
                Value.fromAnyObjC(value: value).map { (key, $0) }
            }
        }
        return mapped.count == value.count ? Dictionary(uniqueKeysWithValues: mapped) : nil
    }
    
    public func toObjC() -> ObjC {
        let out = NSMutableDictionary(capacity: count)
        for (key, val) in self {
            out.setObject(val.toObjC(), forKey: key.toObjC())
        }
        return out
    }
}
