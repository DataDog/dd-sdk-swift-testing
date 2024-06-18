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

@objc public final class DDSuiteTagItrSkippable: DDTag {
    @objc static func tag() -> DDSuiteTagItrSkippable {
        DDSuiteTagItrSkippable(tag: DynamicTag.itrSkippableType.any)
    }
}

@objc public final class DDTestTagItrSkippable: DDTag {
    @objc static func tag() -> DDTestTagItrSkippable {
        DDTestTagItrSkippable(tag: DynamicTag.itrSkippableInstanceMethod.any)
    }
}

extension XCTestCase {
    class var unskippableMethods: [String] {
        guard let tags = maybeTypeTags else { return [] }
        let skippable = tags.tagged(by: DynamicTag.itrSkippableInstanceMethod, prefixed: "test")
        // Our type was marked as "skippable = false"
        if let typeTag = tags.tagged(by: DynamicTag.itrSkippableType).first, !tags[typeTag]! {
            // Check do we have tests explicitly marked as skippable
            let canSkip = skippable.filter { tags[$0]! }.map { $0.to }.asSet
            // We don't have them
            guard canSkip.count > 0 else { return allTestNames }
            // We have them. Filter them from all tests.
            return allTestNames.filter { !canSkip.contains($0) }
        }
        // Our type was not marked. Check all methods where skippable == false
        return skippable.filter { !tags[$0]! }.map { $0.to }
    }
    
    private static var allTestNames: [String] {
        var count: Int32 = 0
        guard let methods = class_copyMethodList(self, &count) else {
            return []
        }
        defer { free(methods) }
        return (0 ..< Int(count)).compactMap {
            String(cString: sel_getName(method_getName(methods[$0])))
        }.filter { $0.hasPrefix("test") && !$0.hasSuffix(":") }
    }
}
