/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */
import Foundation
internal import XCTest

protocol XCTestTag: TestTag {
    func parse(tags: borrowing TypeTags, test: String) -> Value?
}

final class XCTestSuiteTags: Identifiable, Sendable {
    typealias ID = ObjectIdentifier
    
    var id: ObjectIdentifier { ObjectIdentifier(_clazz) }
    
    private let _clazz: XCTestCase.Type
    
    // XCTest is synchronous so it's not synchronized
    nonisolated(unsafe) private var _tagsSet: Bool = false
    nonisolated(unsafe) private var _tags: TypeTags? = nil
    
    var tags: TypeTags? {
        if _tagsSet { return _tags }
        _tags = _clazz.maybeTypeTags
        _tagsSet = true
        return _tags
    }
    
    init(for clazz: XCTestCase.Type) {
        self._clazz = clazz
    }
    
    func tags(for test: String) -> XCTestTags {
        .init(suite: self, test: test)
    }
}

struct XCTestTags: TestTags {
    let suite: XCTestSuiteTags
    let test: String
        
    init(suite: XCTestSuiteTags, test: String) {
        self.suite = suite
        self.test = test
    }
    
    func get<T: TestTag>(tag: T) -> T.Value? {
        guard let tag = tag as? any XCTestTag else {
            return nil
        }
        guard let tags = suite.tags else {
            return nil
        }
        // have to cast because normal types work from macOS 13 only
        return tag.parse(tags: tags, test: test) as! T.Value?
    }
}

// Retriable tag
public extension InstanceMethodTag where T: NSObject, V == Bool {
    static var retriable: Self { "dd.retriable" }
}

public extension TypeTag where T: NSObject, V == Bool {
    static var retriable: Self { "dd.retriable" }
}

public extension DynamicTag where V == Bool {
    static var retriableType: Self { Self(name: "dd.retriable", tagType: .forType) }
    static var retriableInstanceMethod: Self { Self(name: "dd.retriable", tagType: .instanceMethod) }
}

@objc public extension DDTag {
    @objc static var retriableType: DDTag { DDTag(tag: .retriableType) }
    @objc static var retriableInstanceMethod: DDTag { DDTag(tag: .retriableInstanceMethod) }
}

extension RetriableTag: XCTestTag {
    func parse(tags: borrowing TypeTags, test: String) -> Bool? {
        var isSuiteRetriable: Bool = true
        var isTestRetriable: Bool? = nil
        if let tag = tags.tagged(dynamic: .retriableType).first {
            isSuiteRetriable = tags[tag] ?? true
        }
        if let tag = tags.tagged(dynamic: .retriableInstanceMethod, prefixed: test).filter({ $0.to == test }).first {
            isTestRetriable = tags[tag]
        }
        return isTestRetriable ?? isSuiteRetriable
    }
}

// Prevent failure suppression tag
public extension InstanceMethodTag where T: NSObject, V == Bool {
    static var preventFailureSuppression: Self { "dd.prevent_failure_suppression" }
}

public extension TypeTag where T: NSObject, V == Bool {
    static var preventFailureSuppression: Self { "dd.prevent_failure_suppression" }
}

public extension DynamicTag where V == Bool {
    static var preventFailureSuppressionType: Self {
        Self(name: "dd.prevent_failure_suppression", tagType: .forType)
    }
    static var preventFailureSuppressionInstanceMethod: Self {
        Self(name: "dd.prevent_failure_suppression", tagType: .instanceMethod)
    }
}

@objc public extension DDTag {
    @objc static var preventFailureSuppressionType: DDTag { DDTag(tag: .preventFailureSuppressionType) }
    @objc static var preventFailureSuppressionInstanceMethod: DDTag {
        DDTag(tag: .preventFailureSuppressionInstanceMethod)
    }
}

extension PreventFailureSuppressionTag: XCTestTag {
    func parse(tags: borrowing TypeTags, test: String) -> Bool? {
        var isSuiteProtected: Bool? = nil
        var isTestProtected: Bool? = nil
        if let tag = tags.tagged(dynamic: .preventFailureSuppressionType).first {
            isSuiteProtected = tags[tag]
        }
        if let tag = tags.tagged(dynamic: .preventFailureSuppressionInstanceMethod, prefixed: test)
            .first(where: { $0.to == test })
        {
            isTestProtected = tags[tag]
        }
        return isTestProtected ?? isSuiteProtected
    }
}
