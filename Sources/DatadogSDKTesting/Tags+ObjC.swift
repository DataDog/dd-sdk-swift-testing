//
//  File.swift
//  
//
//  Created by Yehor Popovych on 04/06/2024.
//

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
        self.init(tag: AnyTag(name: name, valueType: ctype, tagType: ttype))
    }
    
    @objc public convenience init(name: String, type ttype: TagType, value: Any) {
        self.init(tag: AnyTag(name: name, valueType: type(of: value), tagType: ttype))
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

@objc public final class DDTypeTags: NSObject, TypeTags {
    public let tags: any TypeTags
    
    public init(tags: any TypeTags) {
        self.tags = tags
    }
    
    @inlinable
    public func tagged<T: SomeTag>(by tag: T, prefixed prefix: String?) -> [AttachedTag<T>] {
        tags.tagged(by: tag, prefixed: prefix)
    }
    
    @inlinable
    public func tags(for type: TagType, prefixed prefix: String?) -> [AttachedTag<AnyTag>] {
        tags.tags(for: type, prefixed: prefix)
    }
    
    @inlinable
    public subscript<T: SomeTag>(tag: AttachedTag<T>) -> T.Value? {
        tags[tag]
    }
    
    @objc public func tagged(by tag: DDTag, prefixed prefix: String?) -> [DDAttachedTag] {
        tags.tagged(by: tag.tag, prefixed: prefix).map{$0.objcTag}
    }
    
    @objc public func tags(for type: TagType, prefixed prefix: String?) -> [DDAttachedTag] {
        tags.tags(for: type, prefixed: prefix).map{$0.objcTag}
    }
    
    @inlinable
    public subscript(tag: DDAttachedTag) -> Any? {
        tags[tag.swiftTag]
    }
}

@objc public protocol DDTaggedType: NSObjectProtocol {
    @objc static var associatedTags: DDTypeTags { get }
}

@objc public final class DDTypeTagger: NSObject {
    public private(set) var tagger: TypeTagger<NSObject>
    
    init<T: TaggedType>(for type: T.Type) {
        self.tagger = TypeTagger<NSObject>(type: T.self)
        super.init()
    }
    
    @objc public func set(value: Any, for tag: DDTag, to name: String) throws {
        try tagger.set(value: value, for: tag.tag, to: name)
    }
    
    @objc public func set(value: Any, for tag: DDTag, method: Selector) throws {
        guard tag.tagType == .instanceMethod || tag.tagType == .staticMethod else {
            throw TagTypeError(type: tag.tagType)
        }
        try set(value: value, for: tag, to: method.description)
    }
    
    @objc public func build() -> DDTypeTags {
        DDTypeTags(tags: tagger.build())
    }
}

extension NSObject: TaggedType {
    public class var typeTags: any TypeTags { associatedTags }
}

@objc extension NSObject: DDTaggedType {
    @objc public class var associatedTags: DDTypeTags {
        withTagger {_ in}
    }
}

@objc extension NSObject {
    @objc public static func withTagger( _ builder: (DDTypeTagger) -> Void) -> DDTypeTags {
        let tagger = DDTypeTagger(for: self)
        builder(tagger)
        return tagger.build()
    }
}

public struct TagTypeError: Error {
    let type: TagType
}
