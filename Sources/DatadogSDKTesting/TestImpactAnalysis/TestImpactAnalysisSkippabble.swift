/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

struct TIASkippableTag: TestTag {
    typealias Value = Bool
}

extension TestTag where Self == TIASkippableTag {
    static var tiaSkippable: Self { .init() }
}

// XCTest
internal import XCTest

public extension InstanceMethodTag where T: NSObject, V == Bool {
    static var tiaSkippable: Self { "dd.tia.skippable" }
}

public extension TypeTag where T: NSObject, V == Bool {
    static var tiaSkippable: Self { "dd.tia.skippable" }
}

public extension DynamicTag where V == Bool {
    static var tiaSkippableType: Self { Self(name: "dd.tia.skippable", tagType: .forType) }
    static var tiaSkippableInstanceMethod: Self { Self(name: "dd.tia.skippable", tagType: .instanceMethod) }
}

@objc public extension DDTag {
    @objc static var tiaSkippableType: DDTag { DDTag(tag: .tiaSkippableType) }
    @objc static var tiaSkippableInstanceMethod: DDTag { DDTag(tag: .tiaSkippableInstanceMethod) }
}

extension TIASkippableTag: XCTestTag {
    func parse(tags: borrowing TypeTags, test: String) -> Bool? {
        var isSuiteSkippable: Bool = true
        var isTestSkippable: Bool? = nil
        if let tag = tags.tagged(dynamic: .tiaSkippableType).first {
            isSuiteSkippable = tags[tag] ?? true
        }
        if let tag = tags.tagged(dynamic: .tiaSkippableInstanceMethod, prefixed: test).filter({ $0.to == test }).first {
            isTestSkippable = tags[tag]
        }
        return isTestSkippable ?? isSuiteSkippable
    }
}

#if canImport(Testing)
import Testing

extension Tag.dd {
    enum tia {
        @Tag static var unskippable: Tag
    }
}

extension TIASkippableTag: STTestTag {
    func parse(tags: borrowing Set<Tag>) -> Bool? {
        !tags.contains(Tag.dd.tia.unskippable)
    }
}
#endif
