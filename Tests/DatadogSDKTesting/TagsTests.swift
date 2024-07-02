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
    
    func testCanFetchAndFilterFinalInheritedClassTags() {
        checkFinalTags(tags: TestFinalInheritedClass.finalTypeTags)
        checkTags(tags: TestFinalInheritedClass.typeTags)
        let dtags = TestFinalInheritedClass.dynamicTypeTags
        XCTAssertNotNil(dtags)
        dtags.map { checkTags(tags: $0) }
        let mtags = TestFinalInheritedClass.maybeTypeTags
        XCTAssertNotNil(mtags)
        mtags.map { checkTags(tags: $0) }
    }
    
    func testCanFetchAndFilterFinalInheritedClassTagsDynamic() {
        let ttype: TaggedType.Type = TestFinalInheritedClass.self
        checkTags(tags: ttype.typeTags)
        let dtags = ttype.dynamicTypeTags
        XCTAssertNotNil(dtags)
        dtags.map { checkTags(tags: $0) }
        let mtags = ttype.maybeTypeTags
        XCTAssertNotNil(mtags)
        mtags.map { checkTags(tags: $0) }
    }
    
    func testCanFetchAndFilterObjcClassTags() {
        checkTags(tags: TestObjcClass.extendableTypeTags())
        checkTags(tags: TestObjcClass.typeTags)
        let dtags = TestObjcClass.dynamicTypeTags
        XCTAssertNotNil(dtags)
        dtags.map { checkTags(tags: $0) }
        let mtags = TestObjcClass.maybeTypeTags
        XCTAssertNotNil(mtags)
        mtags.map { checkTags(tags: $0) }
    }
    
    func testCanFetchAndFilterObjcClassTagsDynamic() {
        let ttype: TaggedType.Type = TestObjcClass.self
        checkTags(tags: ttype.typeTags)
        let dtags = ttype.dynamicTypeTags
        XCTAssertNotNil(dtags)
        dtags.map { checkTags(tags: $0) }
        let mtags = ttype.maybeTypeTags
        XCTAssertNotNil(mtags)
        mtags.map { checkTags(tags: $0) }
    }
    
    func testCanFetchAndFilterObjcDDClassTags() {
        checkTags(tags: TestObjcDDClass.attachedTypeTags())
        let mtags = TestObjcDDClass.maybeTypeTags
        XCTAssertNotNil(mtags)
        mtags.map { checkTags(tags: $0) }
    }
    
    func testCanFetchAndFilterObjcDDClassTagsDynamic() {
        let ttype: (DDTaggedType & MaybeTaggedType).Type = TestObjcDDClass.self
        checkTags(tags: ttype.attachedTypeTags())
        let mtags = ttype.maybeTypeTags
        XCTAssertNotNil(mtags)
        mtags.map { checkTags(tags: $0) }
    }
}

private extension TagsTests {
    func checkTags(tags: TypeTags, child: Bool = false) {
        checkTypeTags(tags: tags, child: child)
        checkInstancePropertyTags(tags: tags, child: child)
        checkInstanceMethodTags(tags: tags, child: child)
        checkStaticPropertyTags(tags: tags, child: child)
        checkStaticMethodTags(tags: tags, child: child)
    }
    
    func checkInstancePropertyTags(tags: TypeTags, child: Bool) {
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
        // Filter by type
        let allBool = tags1.filter { $0.tag.eq(to: DynamicTag.testInstancePropertyBoolTag) }
        let allInt = tags1.filter { $0.tag.eq(to: DynamicTag.testInstancePropertyIntTag) }
        if child {
            XCTAssertEqual(allBool.count, 2)
            let parentBool = allBool.filter { $0.to == "test1var" }
            let childBool = allBool.filter { $0.to == "test11var" }
            XCTAssertEqual(parentBool.count, 1)
            XCTAssertEqual(childBool.count, 1)
            XCTAssertEqual(parentBool.first?.tag.tagType, .instanceProperty)
            XCTAssertEqual(childBool.first?.tag.tagType, .instanceProperty)
            XCTAssertEqual(allInt.count, 2)
            let parentInt = allBool.filter { $0.to == "test1var" }
            let childInt = allBool.filter { $0.to == "test11var" }
            XCTAssertEqual(parentInt.count, 1)
            XCTAssertEqual(childInt.count, 1)
            XCTAssertEqual(parentInt.first?.tag.tagType, .instanceProperty)
            XCTAssertEqual(childInt.first?.tag.tagType, .instanceProperty)
        } else {
            XCTAssertEqual(allBool.count, 1)
            XCTAssertEqual(allBool.first?.tag.tagType, .instanceProperty)
            XCTAssertEqual(allBool.first?.to, "test1var")
            XCTAssertEqual(allInt.count, 1)
            XCTAssertEqual(allInt.first?.tag.tagType, .instanceProperty)
            XCTAssertEqual(allInt.first?.to, "test1var")
        }
    }
    
    func checkInstanceMethodTags(tags: TypeTags, child: Bool) {
        // Int instance method
        let tagsInt1 = tags.tagged(dynamic: .testInstanceMethodIntTag)
        let tagsInt2 = tags.tagged(dynamic: .testInstanceMethodIntTag, prefixed: "test")
        let tagsInt3 = tags.tagged(dynamic: .testInstanceMethodIntTag, prefixed: "test3")
        XCTAssertEqual(tagsInt1, tagsInt2)
        XCTAssertEqual(tagsInt3, [])
        if child {
            XCTAssertEqual(tagsInt1.count, 2)
            let parent = tagsInt1.filter { $0.to == "test2func" }
            let child = tagsInt1.filter { $0.to == "test12func" }
            XCTAssertNotEqual(parent, [])
            XCTAssertNotEqual(child, [])
            XCTAssertEqual(parent, tags.tagged(by: .testInstanceMethodIntTag, prefixed: "test2f"))
            XCTAssertEqual(child, tags.tagged(by: .testInstanceMethodIntTag, prefixed: "test12"))
            XCTAssertEqual(parent.first.map{tags[$0]}, 345)
            XCTAssertEqual(child.first.map{tags[$0]}, 333)
        } else {
            XCTAssertEqual(tagsInt1.count, 1)
            XCTAssertEqual(tagsInt1.first.map{tags[$0]}, 345)
            XCTAssertEqual(tagsInt1.first?.to, "test2func")
        }
        // Bool instance method
        let tagsBool1 = tags.tagged(dynamic: .testInstanceMethodBoolTag)
        let tagsBool2 = tags.tagged(dynamic: .testInstanceMethodBoolTag, prefixed: "test")
        let tagsBool3 = tags.tagged(dynamic: .testInstanceMethodBoolTag, prefixed: "test11")
        XCTAssertEqual(tagsBool1, tagsBool2)
        XCTAssertEqual(tagsBool3, [])
        if child {
            XCTAssertEqual(tagsBool1.count, 2)
            let parent = tagsBool1.filter { $0.to == "test2func" }
            let child = tagsBool1.filter { $0.to == "test12func" }
            XCTAssertNotEqual(parent, [])
            XCTAssertNotEqual(child, [])
            XCTAssertEqual(parent, tags.tagged(by: .testInstanceMethodBoolTag, prefixed: "test2f"))
            XCTAssertEqual(child, tags.tagged(by: .testInstanceMethodBoolTag, prefixed: "test12"))
            XCTAssertEqual(parent.first.map{tags[$0]}, false)
            XCTAssertEqual(child.first.map{tags[$0]}, false)
        } else {
            XCTAssertEqual(tagsBool1.count, 1)
            XCTAssertEqual(tagsBool1.first.map{tags[$0]}, false)
            XCTAssertEqual(tagsBool1.first?.to, "test2func")
        }
        // All selectors
        let tags1 = tags.tags(for: .instanceMethod)
        let tags2 = tags.tags(for: .instanceMethod, prefixed: "test")
        let tags3 = tags.tags(for: .instanceMethod, prefixed: "test10")
        XCTAssertEqual(tags1, tags2)
        XCTAssertEqual(tags3, [])
        XCTAssertEqual(tags1.count, child ? 4 : 2)
        // Filter by type
        let allBool = tags1.filter { $0.tag.eq(to: DynamicTag.testInstanceMethodBoolTag) }
        let allInt = tags1.filter { $0.tag.eq(to: DynamicTag.testInstanceMethodIntTag) }
        if child {
            XCTAssertEqual(allBool.count, 2)
            let parentBool = allBool.filter { $0.to == "test2func" }
            let childBool = allBool.filter { $0.to == "test12func" }
            XCTAssertEqual(parentBool.count, 1)
            XCTAssertEqual(childBool.count, 1)
            XCTAssertEqual(parentBool.first?.tag.tagType, .instanceMethod)
            XCTAssertEqual(childBool.first?.tag.tagType, .instanceMethod)
            XCTAssertEqual(allInt.count, 2)
            let parentInt = allBool.filter { $0.to == "test2func" }
            let childInt = allBool.filter { $0.to == "test12func" }
            XCTAssertEqual(parentInt.count, 1)
            XCTAssertEqual(childInt.count, 1)
            XCTAssertEqual(parentInt.first?.tag.tagType, .instanceMethod)
            XCTAssertEqual(childInt.first?.tag.tagType, .instanceMethod)
        } else {
            XCTAssertEqual(allBool.count, 1)
            XCTAssertEqual(allBool.first?.tag.tagType, .instanceMethod)
            XCTAssertEqual(allBool.first?.to, "test2func")
            XCTAssertEqual(allInt.count, 1)
            XCTAssertEqual(allInt.first?.tag.tagType, .instanceMethod)
            XCTAssertEqual(allInt.first?.to, "test2func")
        }
    }
    
    func checkStaticPropertyTags(tags: TypeTags, child: Bool) {
        // Int static property
        let tagsInt1 = tags.tagged(dynamic: .testStaticPropertyIntTag)
        let tagsInt2 = tags.tagged(dynamic: .testStaticPropertyIntTag, prefixed: "test")
        let tagsInt3 = tags.tagged(dynamic: .testStaticPropertyIntTag, prefixed: "test2")
        XCTAssertEqual(tagsInt1, tagsInt2)
        XCTAssertEqual(tagsInt3, [])
        if child {
            XCTAssertEqual(tagsInt1.count, 2)
            let parent = tagsInt1.filter { $0.to == "test3staticVar" }
            let child = tagsInt1.filter { $0.to == "test13staticVar" }
            XCTAssertNotEqual(parent, [])
            XCTAssertNotEqual(child, [])
            XCTAssertEqual(parent, tags.tagged(by: .testStaticPropertyIntTag, prefixed: "test3s"))
            XCTAssertEqual(child, tags.tagged(by: .testStaticPropertyIntTag, prefixed: "test13"))
            XCTAssertEqual(parent.first.map{tags[$0]}, 567)
            XCTAssertEqual(child.first.map{tags[$0]}, 4444)
        } else {
            XCTAssertEqual(tagsInt1.count, 1)
            XCTAssertEqual(tagsInt1.first.map{tags[$0]}, 567)
            XCTAssertEqual(tagsInt1.first?.to, "test3staticVar")
        }
        // String static property
        let tagsString1 = tags.tagged(dynamic: .testStaticPropertyStringTag)
        let tagsString2 = tags.tagged(dynamic: .testStaticPropertyStringTag, prefixed: "test")
        let tagsString3 = tags.tagged(dynamic: .testStaticPropertyStringTag, prefixed: "test2")
        XCTAssertEqual(tagsString1, tagsString2)
        XCTAssertEqual(tagsString3, [])
        if child {
            XCTAssertEqual(tagsString1.count, 2)
            let parent = tagsString1.filter { $0.to == "test3staticVar" }
            let child = tagsString1.filter { $0.to == "test13staticVar" }
            XCTAssertNotEqual(parent, [])
            XCTAssertNotEqual(child, [])
            XCTAssertEqual(parent, tags.tagged(by: .testStaticPropertyStringTag, prefixed: "test3s"))
            XCTAssertEqual(child, tags.tagged(by: .testStaticPropertyStringTag, prefixed: "test13"))
            XCTAssertEqual(parent.first.map{tags[$0]}, "staticProp")
            XCTAssertEqual(child.first.map{tags[$0]}, "staticProp1")
        } else {
            XCTAssertEqual(tagsString1.count, 1)
            XCTAssertEqual(tagsString1.first.map{tags[$0]}, "staticProp")
            XCTAssertEqual(tagsString1.first?.to, "test3staticVar")
        }
        // All selectors
        let tags1 = tags.tags(for: .staticProperty)
        let tags2 = tags.tags(for: .staticProperty, prefixed: "test")
        let tags3 = tags.tags(for: .staticProperty, prefixed: "test10")
        XCTAssertEqual(tags1, tags2)
        XCTAssertEqual(tags3, [])
        XCTAssertEqual(tags1.count, child ? 4 : 2)
        // Filter by type
        let allBool = tags1.filter { $0.tag.eq(to: DynamicTag.testStaticPropertyStringTag) }
        let allInt = tags1.filter { $0.tag.eq(to: DynamicTag.testStaticPropertyIntTag) }
        if child {
            XCTAssertEqual(allBool.count, 2)
            let parentBool = allBool.filter { $0.to == "test3staticVar" }
            let childBool = allBool.filter { $0.to == "test13staticVar" }
            XCTAssertEqual(parentBool.count, 1)
            XCTAssertEqual(childBool.count, 1)
            XCTAssertEqual(parentBool.first?.tag.tagType, .staticProperty)
            XCTAssertEqual(childBool.first?.tag.tagType, .staticProperty)
            XCTAssertEqual(allInt.count, 2)
            let parentInt = allBool.filter { $0.to == "test3staticVar" }
            let childInt = allBool.filter { $0.to == "test13staticVar" }
            XCTAssertEqual(parentInt.count, 1)
            XCTAssertEqual(childInt.count, 1)
            XCTAssertEqual(parentInt.first?.tag.tagType, .staticProperty)
            XCTAssertEqual(childInt.first?.tag.tagType, .staticProperty)
        } else {
            XCTAssertEqual(allBool.count, 1)
            XCTAssertEqual(allBool.first?.tag.tagType, .staticProperty)
            XCTAssertEqual(allBool.first?.to, "test3staticVar")
            XCTAssertEqual(allInt.count, 1)
            XCTAssertEqual(allInt.first?.tag.tagType, .staticProperty)
            XCTAssertEqual(allInt.first?.to, "test3staticVar")
        }
    }
    
    func checkStaticMethodTags(tags: TypeTags, child: Bool) {
        // Int instance method
        let tagsInt1 = tags.tagged(dynamic: .testStaticMethodIntTag)
        let tagsInt2 = tags.tagged(dynamic: .testStaticMethodIntTag, prefixed: "test")
        let tagsInt3 = tags.tagged(dynamic: .testStaticMethodIntTag, prefixed: "test3")
        XCTAssertEqual(tagsInt1, tagsInt2)
        XCTAssertEqual(tagsInt3, [])
        if child {
            XCTAssertEqual(tagsInt1.count, 2)
            let parent = tagsInt1.filter { $0.to == "test4staticFunc" }
            let child = tagsInt1.filter { $0.to == "test14staticFunc" }
            XCTAssertNotEqual(parent, [])
            XCTAssertNotEqual(child, [])
            XCTAssertEqual(parent, tags.tagged(by: .testStaticMethodIntTag, prefixed: "test4s"))
            XCTAssertEqual(child, tags.tagged(by: .testStaticMethodIntTag, prefixed: "test14"))
            XCTAssertEqual(parent.first.map{tags[$0]}, 7890)
            XCTAssertEqual(child.first.map{tags[$0]}, 55555)
        } else {
            XCTAssertEqual(tagsInt1.count, 1)
            XCTAssertEqual(tagsInt1.first.map{tags[$0]}, 7890)
            XCTAssertEqual(tagsInt1.first?.to, "test4staticFunc")
        }
        // Bool instance method
        let tagsBool1 = tags.tagged(dynamic: .testStaticMethodBoolTag)
        let tagsBool2 = tags.tagged(dynamic: .testStaticMethodBoolTag, prefixed: "test")
        let tagsBool3 = tags.tagged(dynamic: .testStaticMethodBoolTag, prefixed: "test11")
        XCTAssertEqual(tagsBool1, tagsBool2)
        XCTAssertEqual(tagsBool3, [])
        if child {
            XCTAssertEqual(tagsBool1.count, 2)
            let parent = tagsBool1.filter { $0.to == "test4staticFunc" }
            let child = tagsBool1.filter { $0.to == "test14staticFunc" }
            XCTAssertNotEqual(parent, [])
            XCTAssertNotEqual(child, [])
            XCTAssertEqual(parent, tags.tagged(by: .testStaticMethodBoolTag, prefixed: "test4s"))
            XCTAssertEqual(child, tags.tagged(by: .testStaticMethodBoolTag, prefixed: "test14"))
            XCTAssertEqual(parent.first.map{tags[$0]}, true)
            XCTAssertEqual(child.first.map{tags[$0]}, true)
        } else {
            XCTAssertEqual(tagsBool1.count, 1)
            XCTAssertEqual(tagsBool1.first.map{tags[$0]}, true)
            XCTAssertEqual(tagsBool1.first?.to, "test4staticFunc")
        }
        // All selectors
        let tags1 = tags.tags(for: .staticMethod)
        let tags2 = tags.tags(for: .staticMethod, prefixed: "test")
        let tags3 = tags.tags(for: .staticMethod, prefixed: "test10")
        XCTAssertEqual(tags1, tags2)
        XCTAssertEqual(tags3, [])
        XCTAssertEqual(tags1.count, child ? 4 : 2)
        // Filter by type
        let allBool = tags1.filter { $0.tag.eq(to: DynamicTag.testStaticMethodBoolTag) }
        let allInt = tags1.filter { $0.tag.eq(to: DynamicTag.testStaticMethodIntTag) }
        if child {
            XCTAssertEqual(allBool.count, 2)
            let parentBool = allBool.filter { $0.to == "test4staticFunc" }
            let childBool = allBool.filter { $0.to == "test14staticFunc" }
            XCTAssertEqual(parentBool.count, 1)
            XCTAssertEqual(childBool.count, 1)
            XCTAssertEqual(parentBool.first?.tag.tagType, .staticMethod)
            XCTAssertEqual(childBool.first?.tag.tagType, .staticMethod)
            XCTAssertEqual(allInt.count, 2)
            let parentInt = allBool.filter { $0.to == "test4staticFunc" }
            let childInt = allBool.filter { $0.to == "test14staticFunc" }
            XCTAssertEqual(parentInt.count, 1)
            XCTAssertEqual(childInt.count, 1)
            XCTAssertEqual(parentInt.first?.tag.tagType, .staticMethod)
            XCTAssertEqual(childInt.first?.tag.tagType, .staticMethod)
        } else {
            XCTAssertEqual(allBool.count, 1)
            XCTAssertEqual(allBool.first?.tag.tagType, .staticMethod)
            XCTAssertEqual(allBool.first?.to, "test4staticFunc")
            XCTAssertEqual(allInt.count, 1)
            XCTAssertEqual(allInt.first?.tag.tagType, .staticMethod)
            XCTAssertEqual(allInt.first?.to, "test4staticFunc")
        }
    }
    
    func checkTypeTags(tags: TypeTags, child: Bool) {
        // Check String
        let typeStr1 = tags.tagged(dynamic: .testTypeStringTag)
        let typeStr2 = tags.tagged(dynamic: .testTypeStringTag, prefixed: "self")
        let typeStr3 = tags.tagged(dynamic: .testTypeStringTag, prefixed: "bad")
        let typeStrValue = child ? "testOverrideString" : "testTypeString"
        XCTAssertEqual(typeStr1, typeStr2)
        XCTAssertEqual(typeStr3, [])
        XCTAssertEqual(typeStr1.count, 1)
        XCTAssertEqual(typeStr1.first?.tag, .testTypeStringTag)
        XCTAssertEqual(typeStr1.first?.to, "self")
        XCTAssertEqual(tags[.to(typeDynamic: .testTypeStringTag)!], typeStrValue)
        XCTAssertEqual(tags[typeStr1[0]], typeStrValue)
        // Check Bool
        let typeBool1 = tags.tagged(dynamic: .testTypeBoolTag)
        let typeBool2 = tags.tagged(dynamic: .testTypeBoolTag, prefixed: "self")
        let typeBool3 = tags.tagged(dynamic: .testTypeBoolTag, prefixed: "bad")
        XCTAssertEqual(typeBool1.count, 1)
        XCTAssertEqual(typeBool1, typeBool2)
        XCTAssertEqual(typeBool3, [])
        XCTAssertEqual(typeBool1.first?.tag, .testTypeBoolTag)
        XCTAssertEqual(typeBool1.first?.to, "self")
        XCTAssertEqual(tags[.to(typeDynamic: .testTypeBoolTag)!], true)
        XCTAssertEqual(tags[typeBool1[0]], true)
        // check int
        let typeInt1 = tags.tagged(dynamic: .testTypeIntTag)
        let typeInt2 = tags.tagged(dynamic: .testTypeIntTag, prefixed: "self")
        let typeInt3 = tags.tagged(dynamic: .testTypeIntTag, prefixed: "bad")
        XCTAssertEqual(typeInt3, [])
        if child {
            XCTAssertEqual(typeInt1.count, 1)
            XCTAssertEqual(typeInt1, typeInt2)
            XCTAssertEqual(typeInt3, [])
            XCTAssertEqual(typeInt1.first?.tag, .testTypeIntTag)
            XCTAssertEqual(typeInt1.first?.to, "self")
            XCTAssertEqual(tags[.to(typeDynamic: .testTypeIntTag)!], 9999)
            XCTAssertEqual(tags[typeInt1[0]], 9999)
        } else {
            XCTAssertEqual(typeInt1, [])
            XCTAssertEqual(typeInt2, [])
        }
        // Check all
        let typeAll1 = tags.tags(for: .forType)
        let typeAll2 = tags.tags(for: .forType, prefixed: "self")
        let typeAll3 = tags.tags(for: .forType, prefixed: "bad")
        XCTAssertEqual(typeAll1, typeAll2)
        XCTAssertEqual(typeAll3, [])
        XCTAssertEqual(typeAll1.count, child ? 3 : 2)
        // Filter by type
        let allBool = typeAll1.filter { $0.tag.eq(to: DynamicTag.testTypeBoolTag) }
        XCTAssertEqual(allBool.count, 1)
        XCTAssertEqual(allBool.first?.to, "self")
        let allString = typeAll1.filter { $0.tag.eq(to: DynamicTag.testTypeStringTag) }
        XCTAssertEqual(allString.count, 1)
        XCTAssertEqual(allString.first?.to, "self")
        if child {
            let allInt = typeAll1.filter { $0.tag.eq(to: DynamicTag.testTypeIntTag) }
            XCTAssertEqual(allInt.count, 1)
            XCTAssertEqual(allInt.first?.to, "self")
        }
    }
    
    func checkFinalTags<T: FinalTaggedType & TagsTestsMarker>(tags: FinalTypeTags<T>, child: Bool = false) {
        checkTags(tags: tags, child: child)
        tagsArrEq(tags.tagged(dynamic: .testTypeBoolTag), tags.tagged(type: .testTypeBoolTag))
        tagsArrEq(tags.tagged(dynamic: .testTypeIntTag), tags.tagged(type: .testTypeIntTag))
        tagsArrEq(tags.tagged(dynamic: .testTypeStringTag), tags.tagged(type: .testTypeStringTag))
        
        tagsArrEq(tags.tagged(dynamic: .testInstancePropertyBoolTag), tags.tagged(instance: .testInstancePropertyBoolTag))
        tagsArrEq(tags.tagged(dynamic: .testInstancePropertyIntTag), tags.tagged(instance: .testInstancePropertyIntTag))
        
        tagsArrEq(tags.tagged(dynamic: .testInstanceMethodBoolTag), tags.tagged(instance: .testInstanceMethodBoolTag))
        tagsArrEq(tags.tagged(dynamic: .testInstanceMethodIntTag), tags.tagged(instance: .testInstanceMethodIntTag))
        
        tagsArrEq(tags.tagged(dynamic: .testStaticPropertyStringTag), tags.tagged(static: .testStaticPropertyStringTag))
        tagsArrEq(tags.tagged(dynamic: .testStaticPropertyIntTag), tags.tagged(static: .testStaticPropertyIntTag))
        
        tagsArrEq(tags.tagged(dynamic: .testStaticMethodBoolTag), tags.tagged(static: .testStaticMethodBoolTag))
        tagsArrEq(tags.tagged(dynamic: .testStaticMethodIntTag), tags.tagged(static: .testStaticMethodIntTag))
    }
    
    func tagsArrEq<T1: SomeTag, T2: SomeTag>(_ arr1: [AttachedTag<T1>], _ arr2: [AttachedTag<T2>]) {
        XCTAssertEqual(arr1.count, arr2.count, "\(arr1) != \(arr2)")
        for xy in zip(arr1, arr2) {
            XCTAssertTrue(xy.0.eq(to: xy.1), "\(arr1) != \(arr2)")
        }
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
        
        class func attachedTypeTags() -> DDTypeTags {
            let tagger = DDTypeTagger.forType(self)!
            // how they will be called from ObjC
            tagger.set(typeTag: .testTypeStringTag, toValue: NSString("testTypeString"))
            tagger.set(typeTag: .testTypeBoolTag, toValue: NSNumber(true))
            tagger.set(tag: .testInstancePropertyIntTag, toValue: NSNumber(123), forMember: "test1var")
            tagger.set(tag: .testInstancePropertyBoolTag, toValue: NSNumber(true), forMember: "test1var")
            tagger.set(tag: .testStaticPropertyIntTag, toValue: NSNumber(567), forMember: "test3staticVar")
            tagger.set(tag: .testStaticMethodIntTag, toValue: NSNumber(7890), forMethod: #selector(test4staticFunc))
            tagger.set(tag: .testStaticMethodBoolTag, toValue: NSNumber(true), forMethod: #selector(test4staticFunc))
            // also we can use Swift types
            tagger.set(tag: .testStaticPropertyStringTag, toValue: "staticProp", forMember: "test3staticVar")
            tagger.set(tag: .testInstanceMethodIntTag, toValue: 345, forMethod: #selector(test2func))
            tagger.set(tag: .testInstanceMethodBoolTag, toValue: false, forMethod: #selector(test2func))
            return tagger.tags()
        }
    }
    
    @objc class TestInheritedObjcClass: TestObjcClass, TagsTestsChildMarker {
        override class func extendableTypeTags() -> ExtendableTypeTags {
            withTagger { tagger in
                setChildTags(tagger: &tagger)
            }
        }
    }
    
    @objc class TestInheritedObjcDDClass: TestObjcDDClass {
        @objc var test11var: String { "test" }
        @objc func test12func() -> Int { 123 }
        @objc static var test13staticVar: Bool { false }
        @objc static func test14staticFunc() -> Double { 654.321 }
        
        override class func attachedTypeTags() -> DDTypeTags {
            let tagger = DDTypeTagger.forType(self)!
            tagger.set(typeTag: .testTypeStringTag, toValue: NSString("testOverrideString"))
            tagger.set(typeTag: .testTypeIntTag, toValue: NSNumber(9999))
            tagger.set(tag: .testInstancePropertyIntTag, toValue: NSNumber(22), forMember: "test11var")
            tagger.set(tag: .testInstancePropertyBoolTag, toValue: NSNumber(true), forMember: "test11var")
            tagger.set(tag: .testInstancePropertyBoolTag, toValue: NSNumber(false), forMember: "test1var")
            tagger.set(tag: .testInstanceMethodIntTag, toValue: NSNumber(333), forMethod: #selector(test12func))
            tagger.set(tag: .testInstanceMethodBoolTag, toValue: NSNumber(false), forMethod: #selector(test12func))
            tagger.set(tag: .testStaticPropertyIntTag, toValue: NSNumber(4444), forMember: "test13staticVar")
            tagger.set(tag: .testStaticPropertyStringTag, toValue: NSString("staticProp1"), forMember: "test13staticVar")
            tagger.set(tag: .testStaticMethodIntTag, toValue: NSNumber(55555), forMethod: #selector(test14staticFunc))
            tagger.set(tag: .testStaticMethodBoolTag, toValue: NSNumber(true), forMethod: #selector(test14staticFunc))
            return tagger.tags()
        }
    }
    
    @objc class TestInheritedSwiftObjcDDClass: TestObjcClass, DDTaggedType {
        @objc var test11var: String { "test" }
        @objc func test12func() -> Int { 123 }
        @objc static var test13staticVar: Bool { false }
        @objc static func test14staticFunc() -> Double { 654.321 }
        
        class func attachedTypeTags() -> DDTypeTags {
            let tagger = DDTypeTagger.forType(self)!
            tagger.set(typeTag: .testTypeStringTag, toValue: NSString("testOverrideString"))
            tagger.set(typeTag: .testTypeIntTag, toValue: NSNumber(9999))
            tagger.set(tag: .testInstancePropertyIntTag, toValue: NSNumber(22), forMember: "test11var")
            tagger.set(tag: .testInstancePropertyBoolTag, toValue: NSNumber(true), forMember: "test11var")
            tagger.set(tag: .testInstancePropertyBoolTag, toValue: NSNumber(false), forMember: "test1var")
            tagger.set(tag: .testInstanceMethodIntTag, toValue: NSNumber(333), forMethod: #selector(test12func))
            tagger.set(tag: .testInstanceMethodBoolTag, toValue: NSNumber(false), forMethod: #selector(test12func))
            tagger.set(tag: .testStaticPropertyIntTag, toValue: NSNumber(4444), forMember: "test13staticVar")
            tagger.set(tag: .testStaticPropertyStringTag, toValue: NSString("staticProp1"), forMember: "test13staticVar")
            tagger.set(tag: .testStaticMethodIntTag, toValue: NSNumber(55555), forMethod: #selector(test14staticFunc))
            tagger.set(tag: .testStaticMethodBoolTag, toValue: NSNumber(true), forMethod: #selector(test14staticFunc))
            return tagger.tags()
        }
    }
    
    @objc final class TestFinalInheritedObjcClass: TestObjcClass, FinalTaggedType, TagsTestsChildMarker {
        static var finalTypeTags: FinalTypeTags<TestFinalInheritedObjcClass> {
            withTagger { tagger in
                setChildTags(tagger: &tagger)
            }
        }
    }
    
    @objc class TestInheritedObjcDDSwiftClass: TestObjcDDClass, ExtendableTaggedType, TagsTestsChildMarker {
        static func extendableTypeTags() -> ExtendableTypeTags {
            withTagger { tagger in
                setChildTags(tagger: &tagger)
            }
        }
    }

    @objc final class TestFinalInheritedObjcDDSwiftClass: TestObjcDDClass, FinalTaggedType, TagsTestsChildMarker {
        static var finalTypeTags: FinalTypeTags<TestFinalInheritedObjcDDSwiftClass> {
            withTagger { tagger in
                setChildTags(tagger: &tagger)
            }
        }
    }
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
        tagger.set(static: .testStaticPropertyStringTag, to: "staticProp1", property: "test13staticVar")
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
    
    static var testTypeIntTag: DDTag {  DDTag(tag: .testTypeIntTag) }
    static var testInstanceMethodIntTag: DDTag { DDTag(tag: .testInstanceMethodIntTag) }
    static var testInstancePropertyIntTag: DDTag { DDTag(tag: .testInstancePropertyIntTag) }
    static var testStaticMethodIntTag: DDTag { DDTag(tag: .testStaticMethodIntTag) }
    static var testStaticPropertyIntTag: DDTag { DDTag(tag: .testStaticPropertyIntTag) }
}
