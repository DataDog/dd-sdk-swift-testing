/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

@objc public class DDTag: NSObject {
    public let tag: AnyTag
    
    @objc public var name: String { tag.name }
    @objc public var tagType: TagType { tag.tagType }
    @objc public var valueType: AnyClass? { tag.valueType as? AnyClass }
    @objc public var valueTypeName: String { String(describing: tag.valueType) }
    
    public init(tag: AnyTag) {
        self.tag = tag
        super.init()
    }
    
    @objc public convenience init(name: String, type ttype: TagType, class ctype: AnyClass) {
        self.init(tag: AnyTag(name: name, tagType: ttype, valueType: ctype))
    }
    
    @objc public convenience init(name: String, type ttype: TagType, value: Any) {
        self.init(tag: AnyTag(name: name, tagType: ttype, valueType: type(of: value)))
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
    public convenience init(tag: AnyTag, to: String) {
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
    
    @objc public func tagged(by tag: DDTag, prefixed prefix: String?) -> [DDAttachedTag] {
        tagged(by: tag.tag, prefixed: prefix).map{$0.objcTag}
    }
    
    @objc public func tags(for type: TagType, prefixed prefix: String?) -> [DDAttachedTag] {
        tags(for: type, prefixed: prefix).map{$0.objcTag}
    }
    
    @objc public subscript(tag: DDAttachedTag) -> Any? {
        self[tag.swiftTag]
    }
}

@objc public protocol DDTaggedType: NSObjectProtocol {
    @objc static var associatedTypeTags: DDTypeTags { get }
}

@objc public final class DDTypeTagger: NSObject {
    public private(set) var tagger: TypeTagger<NSObject>
    
    private init<T: DDTaggedType & MaybeTaggedType>(for type: T.Type) {
        self.tagger = TypeTagger<NSObject>(type: T.self)
        super.init()
    }
    
    @objc public func set(tag: DDTag, to value: Any, for name: String) throws {
        try tagger.set(any: tag.tag, to: value, for: name)
    }
    
    @objc public func set(tag: DDTag, to value: Any, forMethod method: Selector) throws {
        guard tag.tagType == .instanceMethod || tag.tagType == .staticMethod else {
            throw TagTypeError(type: tag.tagType)
        }
        try set(tag: tag, to: value, for: method.description)
    }
    
    @objc static func forType(_ type: NSObject.Type) -> DDTypeTagger? {
        (type as? (DDTaggedType & MaybeTaggedType).Type).map { Self(for: $0) }
    }
    
    @objc public func tags() -> DDTypeTags { tagger.tags() }
}

public extension TypeTagger where T: NSObject {
    func tags() -> DDTypeTags {
        DDTypeTags(parent: parentTags, tags: typeTags)
    }
}

extension NSObject: MaybeTaggedType {
    public static var maybeTypeTags: TypeTags? {
        switch self {
        case let tagged as TaggedType.Type: return tagged.dynamicTypeTags
        case let tagged as DDTaggedType.Type: return tagged.associatedTypeTags
        default: return nil
        }
    }
}

public struct TagTypeError: Error {
    let type: TagType
}
