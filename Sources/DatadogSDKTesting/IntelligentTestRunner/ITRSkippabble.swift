/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import XCTest

public extension InstanceMethodTag where T: NSObject, V == Bool {
    static var itrSkippable: Self { "ITRSkippable" }
}

public extension TypeTag where T: NSObject, V == Bool {
    static var itrSkippable: Self { "ITRSkippable" }
}

public extension DynamicTag where V == Bool {
    static var itrSkippableType: Self { Self(name: "ITRSkippable", tagType: .forType) }
    static var itrSkippableInstanceMethod: Self { Self(name: "ITRSkippable", tagType: .instanceMethod) }
}

@objc public extension DDTag {
    @objc static var itrSkippableType: DDTag { DDTag(tag: .itrSkippableType) }
    @objc static var itrSkippableInstanceMethod: DDTag { DDTag(tag: .itrSkippableInstanceMethod) }
}

final class UnskippableMethodChecker {
    let isSuiteUnskippable: Bool
    let skippableMethods: [String: Bool]
    
    init(for type: XCTestCase.Type) {
        if let tags = type.maybeTypeTags {
            let pairs = tags.tagged(dynamic: .itrSkippableInstanceMethod,
                                    prefixed: "test")
                .compactMap { tag in
                    tags[tag].map { (tag.to, $0) }
                }
            skippableMethods = Dictionary(uniqueKeysWithValues: pairs)
            isSuiteUnskippable = tags.tagged(dynamic: .itrSkippableType).first
                .flatMap { tags[$0] }.map { !$0 } ?? false
        } else {
            isSuiteUnskippable = false
            skippableMethods = [:]
        }
    }
    
    @inlinable func canSkip(method name: String) -> Bool {
        skippableMethods[name] ?? !isSuiteUnskippable
    }
}

extension XCTestCase {
    class var unskippableMethods: UnskippableMethodChecker {
        UnskippableMethodChecker(for: self)
    }
}
