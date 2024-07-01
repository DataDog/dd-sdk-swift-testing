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
        checkTags(tags: TestStruct.typeTags)
        let dtags = TestStruct.dynamicTypeTags
        XCTAssertNotNil(dtags)
        dtags.map { checkTags(tags: $0) }
        let mtags = TestStruct.maybeTypeTags
        XCTAssertNotNil(mtags)
        mtags.map { checkTags(tags: $0) }
    }
    
    func testCanFetchAndFilterStructTagsDynamic() {
        let ttype: TaggedType.Type = TestStruct.self
        checkTags(tags: ttype.typeTags)
        let dtags = ttype.dynamicTypeTags
        XCTAssertNotNil(dtags)
        dtags.map { checkTags(tags: $0) }
        let mtags = ttype.maybeTypeTags
        XCTAssertNotNil(mtags)
        mtags.map { checkTags(tags: $0) }
    }
    
    func testCanFetchAndFilterFinalClassTags() {
        checkFinalTags(tags: TestFinalClass.finalTypeTags)
        checkTags(tags: TestFinalClass.typeTags)
        let dtags = TestFinalClass.dynamicTypeTags
        XCTAssertNotNil(dtags)
        dtags.map { checkTags(tags: $0) }
        let mtags = TestFinalClass.maybeTypeTags
        XCTAssertNotNil(mtags)
        mtags.map { checkTags(tags: $0) }
    }
    
    func testCanFetchAndFilterFinalClassTagsDynamic() {
        let ttype: TaggedType.Type = TestFinalClass.self
        checkTags(tags: ttype.typeTags)
        let dtags = ttype.dynamicTypeTags
        XCTAssertNotNil(dtags)
        dtags.map { checkTags(tags: $0) }
        let mtags = ttype.maybeTypeTags
        XCTAssertNotNil(mtags)
        mtags.map { checkTags(tags: $0) }
    }
    
    func testCanFetchAndFilterClassTags() {
        checkTags(tags: TestClass.extendableTypeTags())
        checkTags(tags: TestClass.typeTags)
        let dtags = TestClass.dynamicTypeTags
        XCTAssertNotNil(dtags)
        dtags.map { checkTags(tags: $0) }
        let mtags = TestClass.maybeTypeTags
        XCTAssertNotNil(mtags)
        mtags.map { checkTags(tags: $0) }
    }
    
    func testCanFetchAndFilterClassTagsDynamic() {
        let ttype: TaggedType.Type = TestClass.self
        checkTags(tags: ttype.typeTags)
        let dtags = ttype.dynamicTypeTags
        XCTAssertNotNil(dtags)
        dtags.map { checkTags(tags: $0) }
        let mtags = ttype.maybeTypeTags
        XCTAssertNotNil(mtags)
        mtags.map { checkTags(tags: $0) }
    }
    
    func testCanFetchAndFilterInheritedClassTags() {
        checkTags(tags: TestInheritedClass.extendableTypeTags(), child: true)
        checkTags(tags: TestInheritedClass.typeTags, child: true)
        let dtags = TestInheritedClass.dynamicTypeTags
        XCTAssertNotNil(dtags)
        dtags.map { checkTags(tags: $0, child: true) }
        let mtags = TestInheritedClass.maybeTypeTags
        XCTAssertNotNil(mtags)
        mtags.map { checkTags(tags: $0, child: true) }
    }
    
    func testCanFetchAndFilterInheritedClassTagsDynamic() {
        let ttype: TaggedType.Type = TestInheritedClass.self
        checkTags(tags: ttype.typeTags, child: true)
        let dtags = ttype.dynamicTypeTags
        XCTAssertNotNil(dtags)
        dtags.map { checkTags(tags: $0, child: true) }
        let mtags = ttype.maybeTypeTags
        XCTAssertNotNil(mtags)
        mtags.map { checkTags(tags: $0, child: true) }
    }
    
    private func checkTags(tags: TypeTags, child: Bool = false) {
        checkTypeTags(tags: tags, child: child)
        checkInstancePropertyTags(tags: tags, child: child)
//        tagger.set(instance: .testInstanceMethodIntTag, to: 345, method: "test2func")
//        tagger.set(instance: .testInstanceMethodBoolTag, to: false, method: "test2func")
//        tagger.set(static: .testStaticPropertyIntTag, to: 567, property: "test3staticVar")
//        tagger.set(static: .testStaticPropertyStringTag, to: "staticProp", property: "test3staticVar")
//        tagger.set(static: .testStaticMethodIntTag, to: 7890, method: "test4staticFunc")
//        tagger.set(static: .testStaticMethodBoolTag, to: true, method: "test4staticFunc")
    }
    
    private func checkInstancePropertyTags(tags: TypeTags, child: Bool) {
        // Int instance property
        let tagsInt1 = tags.tagged(dynamic: .testInstancePropertyIntTag)
        let tagsInt2 = tags.tagged(dynamic: .testInstancePropertyIntTag, prefixed: "test")
        let tagsInt3 = tags.tagged(dynamic: .testInstancePropertyIntTag, prefixed: "test2")
        XCTAssertEqual(tagsInt1, tagsInt2)
        XCTAssertEqual(tagsInt3, [])
        if child {
            XCTAssertEqual(tagsInt1.count, 2)
            let parent = tagsInt1.filter { $0.to == "test1var" }
            let child = tagsInt1.filter { $0.to == "test11var" }
            XCTAssertNotEqual(parent, [])
            XCTAssertNotEqual(child, [])
            XCTAssertEqual(parent, tags.tagged(by: .testInstancePropertyIntTag, prefixed: "test1v"))
            XCTAssertEqual(child, tags.tagged(by: .testInstancePropertyIntTag, prefixed: "test11"))
            XCTAssertEqual(parent.first.map{tags[$0]}, 123)
            XCTAssertEqual(child.first.map{tags[$0]}, 22)
        } else {
            XCTAssertEqual(tagsInt1.count, 1)
            XCTAssertEqual(tagsInt1.first.map{tags[$0]}, 123)
            XCTAssertEqual(tagsInt1.first?.to, "test1var")
        }
        // Bool instance property
        let tagsBool1 = tags.tagged(dynamic: .testInstancePropertyBoolTag)
        let tagsBool2 = tags.tagged(dynamic: .testInstancePropertyBoolTag, prefixed: "test")
        let tagsBool3 = tags.tagged(dynamic: .testInstancePropertyBoolTag, prefixed: "test2")
        XCTAssertEqual(tagsBool1, tagsBool2)
        XCTAssertEqual(tagsBool3, [])
        if child {
            XCTAssertEqual(tagsBool1.count, 2)
            let parent = tagsBool1.filter { $0.to == "test1var" }
            let child = tagsBool1.filter { $0.to == "test11var" }
            XCTAssertNotEqual(parent, [])
            XCTAssertNotEqual(child, [])
            XCTAssertEqual(parent, tags.tagged(by: .testInstancePropertyBoolTag, prefixed: "test1v"))
            XCTAssertEqual(child, tags.tagged(by: .testInstancePropertyBoolTag, prefixed: "test11"))
            XCTAssertEqual(parent.first.map{tags[$0]}, false)
            XCTAssertEqual(child.first.map{tags[$0]}, true)
        } else {
            XCTAssertEqual(tagsBool1.count, 1)
            XCTAssertEqual(tagsBool1.first.map{tags[$0]}, true)
            XCTAssertEqual(tagsBool1.first?.to, "test1var")
        }
        // All selectors
        let tags1 = tags.tags(for: .instanceProperty)
        let tags2 = tags.tags(for: .instanceProperty, prefixed: "test")
        let tags3 = tags.tags(for: .instanceProperty, prefixed: "test3")
        XCTAssertEqual(tags1, tags2)
        XCTAssertEqual(tags3, [])
        XCTAssertEqual(tags1.count, child ? 4 : 2)
//        // Filter by type
//        let allBool = tags1.filter { $0.tag.eq(to: DynamicTag.testInstancePropertyBoolTag) }
//
//        if child {
//
//            let allString = typeAll1.filter { $0.tag.eq(to: DynamicTag.testTypeStringTag) }
//            XCTAssertEqual(allString.count, 2)
//            XCTAssertEqual(allString[0].to, "\(cType)")
//            XCTAssertEqual(allString[1].to, "\(type)")
//            let allInt = typeAll1.filter { $0.tag.eq(to: DynamicTag.testTypeIntTag) }
//            XCTAssertEqual(allInt.count, 1)
//            XCTAssertEqual(allInt.first?.to, "\(cType)")
//        } else {
//            let allString = typeAll1.filter { $0.tag.eq(to: DynamicTag.testTypeStringTag) }
//            XCTAssertEqual(allString.count, 1)
//            XCTAssertEqual(allString.first?.to, "\(type)")
//        }
    }
    
    private func checkTypeTags(tags: TypeTags, child: Bool) {
        // Check String
        let typeStr1 = tags.tagged(dynamic: .testTypeStringTag)
        let typeStr2 = tags.tagged(dynamic: .testTypeStringTag, prefixed: "@")
        let typeStr3 = tags.tagged(dynamic: .testTypeStringTag, prefixed: "bad")
        let typeStrValue = child ? "testOverrideString" : "testTypeString"
        XCTAssertEqual(typeStr1, typeStr2)
        XCTAssertEqual(typeStr3, [])
        XCTAssertEqual(typeStr1.count, 1)
        XCTAssertEqual(typeStr1.first?.tag, .testTypeStringTag)
        XCTAssertEqual(typeStr1.first?.to, "@")
        XCTAssertEqual(tags[.to(typeDynamic: .testTypeStringTag)!], typeStrValue)
        XCTAssertEqual(tags[typeStr1[0]], typeStrValue)
        // Check Bool
        let typeBool1 = tags.tagged(dynamic: .testTypeBoolTag)
        let typeBool2 = tags.tagged(dynamic: .testTypeBoolTag, prefixed: "@")
        let typeBool3 = tags.tagged(dynamic: .testTypeBoolTag, prefixed: "bad")
        XCTAssertEqual(typeBool1.count, 1)
        XCTAssertEqual(typeBool1, typeBool2)
        XCTAssertEqual(typeBool3, [])
        XCTAssertEqual(typeBool1.first?.tag, .testTypeBoolTag)
        XCTAssertEqual(typeBool1.first?.to, "@")
        XCTAssertEqual(tags[.to(typeDynamic: .testTypeBoolTag)!], true)
        XCTAssertEqual(tags[typeBool1[0]], true)
        // check int
        let typeInt1 = tags.tagged(dynamic: .testTypeIntTag)
        let typeInt2 = tags.tagged(dynamic: .testTypeIntTag, prefixed: "@")
        let typeInt3 = tags.tagged(dynamic: .testTypeIntTag, prefixed: "bad")
        XCTAssertEqual(typeInt3, [])
        if child {
            XCTAssertEqual(typeInt1.count, 1)
            XCTAssertEqual(typeInt1, typeInt2)
            XCTAssertEqual(typeInt3, [])
            XCTAssertEqual(typeInt1.first?.tag, .testTypeIntTag)
            XCTAssertEqual(typeInt1.first?.to, "@")
            XCTAssertEqual(tags[.to(typeDynamic: .testTypeIntTag)!], 9999)
            XCTAssertEqual(tags[typeInt1[0]], 9999)
        } else {
            XCTAssertEqual(typeInt1, [])
            XCTAssertEqual(typeInt2, [])
        }
        // Check all
        let typeAll1 = tags.tags(for: .forType)
        let typeAll2 = tags.tags(for: .forType, prefixed: "@")
        let typeAll3 = tags.tags(for: .forType, prefixed: "bad")
        XCTAssertEqual(typeAll1, typeAll2)
        XCTAssertEqual(typeAll3, [])
        XCTAssertEqual(typeAll1.count, child ? 3 : 2)
        // Filter by type
        let allBool = typeAll1.filter { $0.tag.eq(to: DynamicTag.testTypeBoolTag) }
        XCTAssertEqual(allBool.count, 1)
        XCTAssertEqual(allBool.first?.to, "@")
        let allString = typeAll1.filter { $0.tag.eq(to: DynamicTag.testTypeStringTag) }
        XCTAssertEqual(allString.count, 1)
        XCTAssertEqual(allString.first?.to, "@")
        if child {
            let allInt = typeAll1.filter { $0.tag.eq(to: DynamicTag.testTypeIntTag) }
            XCTAssertEqual(allInt.count, 1)
            XCTAssertEqual(allInt.first?.to, "@")
        }
    }
    
    private func checkFinalTags<T: FinalTaggedType>(tags: FinalTypeTags<T>, child: Bool = false) {
        checkTags(tags: tags, child: child)
    }
}

extension TagsTests {
    struct TestStruct: TagsTestsMarker, FinalTaggedType {
        static let finalTypeTags: FinalTypeTags<Self> = {
            withTagger { tagger in
                setTags(tagger: &tagger)
            }
        }()
    }
    
    final class TestFinalClass: TagsTestsMarker, FinalTaggedType {
        static let finalTypeTags: FinalTypeTags<TestFinalClass> = {
            withTagger { tagger in
                setTags(tagger: &tagger)
            }
        }()
    }
    
    class TestClass: TagsTestsMarker, ExtendableTaggedType {
        class func extendableTypeTags() -> ExtendableTypeTags {
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
        
        override class func extendableTypeTags() -> ExtendableTypeTags {
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
        class func extendableTypeTags() -> ExtendableTypeTags {
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
        
        static func addTypeTags(_ tagger: DDTypeTagger) {
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
        tagger.set(instance: .testInstancePropertyIntTag, to: 123, property: \.test1var)
        tagger.set(instance: .testInstancePropertyBoolTag, to: true, property: \.test1var)
        tagger.set(instance: .testInstanceMethodIntTag, to: 345, method: "test2func")
        tagger.set(instance: .testInstanceMethodBoolTag, to: false, method: "test2func")
        tagger.set(static: .testStaticPropertyIntTag, to: 567, property: "test3staticVar")
        tagger.set(static: .testStaticPropertyStringTag, to: "staticProp", property: "test3staticVar")
        tagger.set(static: .testStaticMethodIntTag, to: 7890, method: "test4staticFunc")
        tagger.set(static: .testStaticMethodBoolTag, to: true, method: "test4staticFunc")
    }
}

extension TagsTestsChildMarker {
    var test11var: String { "test" }
    func test12func() -> Int { 123 }
    static var test13staticVar: Bool { false }
    static func test14staticFunc() -> Double { 654.321 }
    static func setChildTags(tagger: inout TypeTagger<Self>) {
        tagger.set(type: .testTypeStringTag, to: "testOverrideString")
        tagger.set(type: .testTypeIntTag, to: 9999)
        tagger.set(instance: .testInstancePropertyIntTag, to: 22, property: \.test11var)
        tagger.set(instance: .testInstancePropertyBoolTag, to: true, property: \.test11var)
        tagger.set(instance: .testInstancePropertyBoolTag, to: false, property: \.test1var)
        tagger.set(instance: .testInstanceMethodIntTag, to: 333, method: "test12func")
        tagger.set(instance: .testInstanceMethodBoolTag, to: false, method: "test12func")
        tagger.set(static: .testStaticPropertyIntTag, to: 4444, property: "test13staticVar")
        tagger.set(static: .testStaticPropertyStringTag, to: "staticProp", property: "test13staticVar")
        tagger.set(static: .testStaticMethodIntTag, to: 55555, method: "test14staticFunc")
        tagger.set(static: .testStaticMethodBoolTag, to: true, method: "test14staticFunc")
    }
}

extension TypeTag where T: TagsTestsMarker, V == String {
    static var testTypeStringTag: Self { "testStringTag" }
}

extension TypeTag where T: TagsTestsMarker, V == Bool {
    static var testTypeBoolTag: Self { "testBoolTag" }
}

extension TypeTag where T: TagsTestsMarker, V == Int {
    static var testTypeIntTag: Self { "testIntTag" }
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
    static var testTypeIntTag: Self {  Self(name: "testIntTag", tagType: .forType) }
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
