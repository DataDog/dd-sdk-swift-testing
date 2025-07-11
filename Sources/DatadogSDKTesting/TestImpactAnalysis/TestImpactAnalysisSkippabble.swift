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

protocol UnskippableMethodCheckerFactory: AnyObject {
    var classId: ObjectIdentifier { get }
    var unskippableMethods: UnskippableMethodChecker { get }
}

final class UnskippableMethodChecker {
    let isSuiteUnskippable: Bool
    let skippableMethods: [String: Bool]
    
    convenience init(for type: XCTestCase.Type) {
        let isSuiteUnskippable: Bool
        let skippableMethods: [String: Bool]
        
        if let tags = type.maybeTypeTags {
            let pairs = tags.tagged(dynamic: .tiaSkippableInstanceMethod,
                                    prefixed: "test")
                .compactMap { tag in
                    tags[tag].map { (tag.to, $0) }
                }
            skippableMethods = Dictionary(uniqueKeysWithValues: pairs)
            isSuiteUnskippable = tags.tagged(dynamic: .tiaSkippableType).first
                .flatMap { tags[$0] }.map { !$0 } ?? false
        } else {
            isSuiteUnskippable = false
            skippableMethods = [:]
        }
        self.init(isSuiteUnskippable: isSuiteUnskippable, skippableMethods: skippableMethods)
    }
    
    init(isSuiteUnskippable: Bool, skippableMethods: [String: Bool]) {
        self.isSuiteUnskippable = isSuiteUnskippable
        self.skippableMethods = skippableMethods
    }
    
    @inlinable func canSkip(method name: String) -> Bool {
        skippableMethods[name] ?? !isSuiteUnskippable
    }
}

extension XCTestCase: UnskippableMethodCheckerFactory {
    var classId: ObjectIdentifier {
        ObjectIdentifier(type(of: self))
    }
    
    var unskippableMethods: UnskippableMethodChecker {
        UnskippableMethodChecker(for: type(of: self))
    }
}
