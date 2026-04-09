/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import XCTest

public extension InstanceMethodTag where T: NSObject, V == Bool {
    static var tiaSkippable: Self { "tia.skippable" }
}

public extension TypeTag where T: NSObject, V == Bool {
    static var tiaSkippable: Self { "tia.skippable" }
}

public extension DynamicTag where V == Bool {
    static var tiaSkippableType: Self { Self(name: "tia.skippable", tagType: .forType) }
    static var tiaSkippableInstanceMethod: Self { Self(name: "tia.skippable", tagType: .instanceMethod) }
}

@objc public extension DDTag {
    @objc static var tiaSkippableType: DDTag { DDTag(tag: .tiaSkippableType) }
    @objc static var tiaSkippableInstanceMethod: DDTag { DDTag(tag: .tiaSkippableInstanceMethod) }
}

struct TIASkippableTag: XCTestTag {
    typealias Value = Bool
    
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

extension TestTag where Self == TIASkippableTag {
    static var tiaSkippable: Self { .init() }
}
