/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting

class UnskippableTypeTaggedTests: XCTestCase, ExtendableTaggedType {
    func testTiaSkippable() {
        let skip = self.unskippableMethods
        XCTAssertFalse(skip.canSkip(method: "testTiaSkippable"))
        XCTAssertFalse(skip.canSkip(method: "testTiaSkippable123"))
    }
    
    static func extendableTypeTags() -> ExtendableTypeTags {
        withTagger { tagger in
            tagger.set(type: .tiaSkippable, to: false)
        }
    }
}

class UnskippableNoTagsTests: XCTestCase {
    func testTiaSkippable() {
        let skip = self.unskippableMethods
        XCTAssertTrue(skip.canSkip(method: "testTiaSkippable"))
        XCTAssertTrue(skip.canSkip(method: "testTiaSkippable123"))
    }
}

final class UnskippableTypeTaggedOverrideTests: XCTestCase, FinalTaggedType {
    func testTiaSkippable() {
        let skip = self.unskippableMethods
        XCTAssertTrue(skip.canSkip(method: "testTiaSkippable"))
        XCTAssertFalse(skip.canSkip(method: "testTiaSkippable123"))
        XCTAssertFalse(skip.canSkip(method: "testTiaSkippable456"))
    }
    
    static let finalTypeTags: FinalTypeTags<UnskippableTypeTaggedOverrideTests> = {
        withTagger { tagger in
            tagger.set(type: .tiaSkippable, to: false)
            tagger.set(instance: .tiaSkippable, to: true, method: "testTiaSkippable")
            tagger.set(instance: .tiaSkippable, to: false, method: "testTiaSkippable456")
        }
    }()
}

class UnskippableMethodTaggedTests: XCTestCase, DDTaggedType {
    func testTiaSkippable() {
        let skip = self.unskippableMethods
        XCTAssertFalse(skip.canSkip(method: "testTiaSkippable"))
        XCTAssertTrue(skip.canSkip(method: "testTiaSkippable123"))
        XCTAssertTrue(skip.canSkip(method: "testTiaSkippable456"))
    }
    
    static func attachedTypeTags() -> DDTypeTags {
        let tagger = DDTypeTagger.forType(self)!
        tagger.set(tag: .tiaSkippableInstanceMethod, toValue: false, forMember: "testTiaSkippable")
        tagger.set(tag: .tiaSkippableInstanceMethod, toValue: true, forMember: "testTiaSkippable456")
        return tagger.tags()
    }
}
