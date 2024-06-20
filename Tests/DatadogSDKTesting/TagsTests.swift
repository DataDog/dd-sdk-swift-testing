/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
import DatadogSDKTesting

final class TagsTests: XCTestCase {
    func testCanFetchAndFilterStructTags() {
        checkFinalTags(tags: TestStruct.finalTypeTags)
        checkTags(tags: TestStruct.typeTags, type: TestStruct.self)
        let dtags = TestStruct.dynamicTypeTags
        XCTAssertNotNil(dtags)
        dtags.map { checkTags(tags: $0, type: TestStruct.self) }
        let mtags = TestStruct.maybeTypeTags
        XCTAssertNotNil(mtags)
        mtags.map { checkTags(tags: $0, type: TestStruct.self) }
    }
    
    func testCanFetchAndFilterStructTagsDynamic() {
        let ttype: TaggedType.Type = TestStruct.self
        checkTags(tags: ttype.typeTags, type: ttype)
        let dtags = ttype.dynamicTypeTags
        XCTAssertNotNil(dtags)
        dtags.map { checkTags(tags: $0, type: ttype) }
        let mtags = ttype.maybeTypeTags
        XCTAssertNotNil(mtags)
        mtags.map { checkTags(tags: $0, type: ttype) }
    }
    
    private func checkTags(tags: TypeTags, type: Any.Type, child: Bool = false) {
        let typeStr1 = tags.tagged(dynamic: .testTypeStringTag)
        let typeStr2 = tags.tagged(dynamic: .testTypeStringTag, prefixed: "Test")
        let typeStr3 = tags.tagged(dynamic: .testTypeStringTag, prefixed: "bad")
        XCTAssertEqual(typeStr1.count, 1)
        XCTAssertEqual(typeStr1, typeStr2)
        XCTAssertEqual(typeStr3, [])
        XCTAssertEqual(typeStr1.first?.tag, .testTypeStringTag)
        XCTAssertEqual(typeStr1.first?.to, "\(type).Type")
        XCTAssertEqual(tags[.to(type: type, dynamic: .testTypeStringTag)!],
                       child ? "testOverrideString" : "testTypeString")
        XCTAssertEqual(tags[typeStr1[0]], child ? "testOverrideString" : "testTypeString")
        
    }
    
    private func checkFinalTags<T: FinalTaggedType>(tags: FinalTypeTags<T>) {
        checkTags(tags: tags, type: T.self)
    }
}

extension TagsTests {
    struct TestStruct: TagsTestsMarker, FinalTaggedType {
        static var finalTypeTags: FinalTypeTags<Self> {
            withTagger { tagger in
                setTags(tagger: &tagger)
            }
        }
    }
    
    final class TestFinalClass: TagsTestsMarker, FinalTaggedType {
        static var finalTypeTags: FinalTypeTags<TestFinalClass> {
            withTagger { tagger in
                setTags(tagger: &tagger)
            }
        }
    }
    
    class TestClass: TagsTestsMarker, ExtendableTaggedType {
        class var extendableTypeTags: ExtendableTypeTags {
            withTagger { tagger in
                setTags(tagger: &tagger)
            }
        }
    }
    
    class TestInheritedClass: TestClass, TagsTestsChildMarker {
        var test11var: String = ""
        func test12func() -> Int { 10 }
        static var test13staticVar: Bool = false
        static func test14staticFunc() -> Double? { nil }
        
        override class var extendableTypeTags: ExtendableTypeTags {
            withTagger { tagger in
                setChildTags(tagger: &tagger)
            }
        }
    }
    
    final class TestFinalInheritedClass: TestClass, FinalTaggedType {
        var test11var: String = ""
        func test12func() -> Int { 10 }
        static var test13staticVar: Bool = false
        static func test14staticFunc() -> Double? { nil }
        
        static var finalTypeTags: FinalTypeTags<TestFinalInheritedClass> {
            withTagger { tagger in
                setTags(tagger: &tagger)
            }
        }
    }
    
    @objc class TestObjcClass: NSObject, ExtendableTaggedType, TagsTestsMarker {
        class var extendableTypeTags: ExtendableTypeTags {
            withTagger { tagger in
                setTags(tagger: &tagger)
            }
        }
    }
    
    @objc class TestObjcDDClass: NSObject, DDTaggedType {
        @objc var test1var: String = ""
        @objc func test2func() -> Int { 10 }
        @objc static var test3staticVar: Bool = false
        @objc static func test4staticFunc() -> Double { 0 }
        
        static func associatedTypeTags() -> DDTypeTags {
            let tagger = DDTypeTagger.forType(TestObjcDDClass.self)!
            // how they will be called from ObjC
            tagger.set(typeTag: .testTypeStringTag, toValue: NSString("testTypeString"))
            tagger.set(typeTag: .testTypeBoolTag, toValue: NSNumber(true))
            tagger.set(tag: .testInstancePropertyIntTag, toValue: NSNumber(123), forMember: "test1var")
            tagger.set(tag: .testInstancePropertyBoolTag, toValue: NSNumber(true), forMember: "test1var")
            tagger.set(tag: .testStaticPropertyIntTag, toValue: NSNumber(567), forMember: "test3staticVar")
            tagger.set(tag: .testStaticPropertyStringTag, toValue: "staticProp", forMember: "test3staticVar")
            tagger.set(tag: .testStaticMethodIntTag, toValue: NSNumber(7890), forMethod: #selector(test4staticFunc))
            tagger.set(tag: .testStaticMethodBoolTag, toValue: NSNumber(true), forMethod: #selector(test4staticFunc))
            // lets try call from Swift
            tagger.set(tag: .testInstanceMethodIntTag, toValue: 345, forMethod: #selector(test2func))
            tagger.set(tag: .testInstanceMethodBoolTag, toValue: false, forMethod: #selector(test2func))
            // return tags
            return tagger.tags()
        }
    }
    
//    @objc class TestInheritedObjcClass: TestObjcClass, DDTaggedType {
//
//    }
//
//    @objc class TestFinalInheritedObjcClass: TestObjcClass, FinalTaggedType {
//
//    }
//
//    @objc class TestInheritedObjcDDClass: TestObjcDDClass {
//
//    }
//
//    @objc class TestFinalInheritedObjcDDClass: TestInheritedObjcDDClass, FinalTaggedType {
//
//    }
}

protocol TagsTestsMarker: TaggedType {
    var test1var: String { get }
    func test2func() -> Int
    static var test3staticVar: Bool { get }
    static func test4staticFunc() -> Double
}

protocol TagsTestsChildMarker: TagsTestsMarker {
    var test11var: String { get }
    func test12func() -> Int
    static var test13staticVar: Bool { get }
    static func test14staticFunc() -> Double
}

extension TagsTestsMarker {
    var test1var: String { "" }
    func test2func() -> Int { 10 }
    static var test3staticVar: Bool { true }
    static func test4staticFunc() -> Double { 123.456 }
    
    static func setTags(tagger: inout TypeTagger<Self>) {
        tagger.set(type: .testTypeStringTag, to: "testTypeString")
        tagger.set(type: .testTypeBoolTag, to: true)
        tagger.set(instance: .testInstancePropertyIntTag, to: 123, for: \.test1var)
        tagger.set(instance: .testInstancePropertyBoolTag, to: true, for: \.test1var)
        tagger.set(instance: .testInstanceMethodIntTag, to: 345, for: "test2func")
        tagger.set(instance: .testInstanceMethodBoolTag, to: false, for: "test2func")
        tagger.set(static: .testStaticPropertyIntTag, to: 567, for: "test3staticVar")
        tagger.set(static: .testStaticPropertyStringTag, to: "staticProp", for: "test3staticVar")
        tagger.set(static: .testStaticMethodIntTag, to: 7890, for: "test4staticFunc")
        tagger.set(static: .testStaticMethodBoolTag, to: true, for: "test4staticFunc")
    }
}

extension TagsTestsChildMarker {
    var test11var: String { "test" }
    func test12func() -> Int { 123 }
    static var test13staticVar: Bool { false }
    static func test14staticFunc() -> Double { 654.321 }
    static func setChildTags(tagger: inout TypeTagger<Self>) {
        tagger.set(type: .testTypeStringTag, to: "testOverrideString")
        tagger.set(type: .testTypeBoolTag, to: false)
        tagger.set(instance: .testInstancePropertyIntTag, to: 123, for: \.test11var)
        tagger.set(instance: .testInstancePropertyBoolTag, to: true, for: \.test11var)
        tagger.set(instance: .testInstancePropertyBoolTag, to: false, for: \.test1var)
        tagger.set(instance: .testInstanceMethodIntTag, to: 345, for: "test12func")
        tagger.set(instance: .testInstanceMethodBoolTag, to: false, for: "test12func")
        tagger.set(static: .testStaticPropertyIntTag, to: 567, for: "test13staticVar")
        tagger.set(static: .testStaticPropertyStringTag, to: "staticProp", for: "test13staticVar")
        tagger.set(static: .testStaticMethodIntTag, to: 7890, for: "test14staticFunc")
        tagger.set(static: .testStaticMethodBoolTag, to: true, for: "test14staticFunc")
    }
}

extension TypeTag where T: TagsTestsMarker, V == String {
    static var testTypeStringTag: Self { "testStringTag" }
}

extension TypeTag where T: TagsTestsMarker, V == Bool {
    static var testTypeBoolTag: Self { "testBoolTag" }
}

extension InstanceMethodTag where T: TagsTestsMarker, V == Int {
    static var testInstanceMethodIntTag: Self { "testIntTag" }
}

extension InstanceMethodTag where T: TagsTestsMarker, V == Bool {
    static var testInstanceMethodBoolTag: Self { "testBoolTag" }
}

extension InstancePropertyTag where T: TagsTestsMarker, V == Int {
    static var testInstancePropertyIntTag: Self { "testIntTag" }
}

extension InstancePropertyTag where T: TagsTestsMarker, V == Bool {
    static var testInstancePropertyBoolTag: Self { "testBoolTag" }
}

extension StaticMethodTag where T: TagsTestsMarker, V == Int {
    static var testStaticMethodIntTag: Self { "testIntTag" }
}

extension StaticMethodTag where T: TagsTestsMarker, V == Bool {
    static var testStaticMethodBoolTag: Self { "testBoolTag" }
}

extension StaticPropertyTag where T: TagsTestsMarker, V == Int {
    static var testStaticPropertyIntTag: Self { "testIntTag" }
}

extension StaticPropertyTag where T: TagsTestsMarker, V == String {
    static var testStaticPropertyStringTag: Self { "testStringTag" }
}

extension DynamicTag where V == String {
    static var testTypeStringTag: Self { Self(name: "testStringTag", tagType: .forType) }
    static var testStaticPropertyStringTag: Self { Self(name: "testStringTag", tagType: .staticProperty) }
}

extension DynamicTag where V == Bool {
    static var testTypeBoolTag: Self {  Self(name: "testBoolTag", tagType: .forType) }
    static var testInstanceMethodBoolTag: Self { Self(name: "testBoolTag", tagType: .instanceMethod) }
    static var testInstancePropertyBoolTag: Self { Self(name: "testBoolTag", tagType: .instanceProperty) }
    static var testStaticMethodBoolTag: Self { Self(name: "testBoolTag", tagType: .staticMethod) }
}

extension DynamicTag where V == Int {
    static var testInstanceMethodIntTag: Self { Self(name: "testIntTag", tagType: .instanceMethod) }
    static var testInstancePropertyIntTag: Self { Self(name: "testIntTag", tagType: .instanceProperty) }
    static var testStaticMethodIntTag: Self { Self(name: "testIntTag", tagType: .staticMethod) }
    static var testStaticPropertyIntTag: Self { Self(name: "testIntTag", tagType: .staticProperty) }
}

extension DDTag {
    static var testTypeStringTag: DDTag { DDTag(tag: .testTypeStringTag) }
    static var testStaticPropertyStringTag: DDTag { DDTag(tag: .testStaticPropertyStringTag) }
    
    static var testTypeBoolTag: DDTag { DDTag(tag: .testTypeBoolTag) }
    static var testInstanceMethodBoolTag: DDTag { DDTag(tag: .testInstanceMethodBoolTag) }
    static var testInstancePropertyBoolTag: DDTag { DDTag(tag: .testInstancePropertyBoolTag) }
    static var testStaticMethodBoolTag: DDTag { DDTag(tag: .testStaticMethodBoolTag) }
    
    static var testInstanceMethodIntTag: DDTag { DDTag(tag: .testInstanceMethodIntTag) }
    static var testInstancePropertyIntTag: DDTag { DDTag(tag: .testInstancePropertyIntTag) }
    static var testStaticMethodIntTag: DDTag { DDTag(tag: .testStaticMethodIntTag) }
    static var testStaticPropertyIntTag: DDTag { DDTag(tag: .testStaticPropertyIntTag) }
}
