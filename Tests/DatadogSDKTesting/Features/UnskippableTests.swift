/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting

class UnskippableTypeTaggedTests: XCTestCase, ExtendableTaggedType {
    func testItrSkippable() {
        let skip = self.unskippableMethods
        XCTAssertFalse(skip.canSkip(method: "testItrSkippable"))
        XCTAssertFalse(skip.canSkip(method: "testItrSkippable123"))
    }
    
    static func extendableTypeTags() -> ExtendableTypeTags {
        withTagger { tagger in
            tagger.set(type: .itrSkippable, to: false)
        }
    }
}

class UnskippableNoTagsTests: XCTestCase {
    func testItrSkippable() {
        let skip = self.unskippableMethods
        XCTAssertTrue(skip.canSkip(method: "testItrSkippable"))
        XCTAssertTrue(skip.canSkip(method: "testItrSkippable123"))
    }
}

final class UnskippableTypeTaggedOverrideTests: XCTestCase, FinalTaggedType {
    func testItrSkippable() {
        let skip = self.unskippableMethods
        XCTAssertTrue(skip.canSkip(method: "testItrSkippable"))
        XCTAssertFalse(skip.canSkip(method: "testItrSkippable123"))
        XCTAssertFalse(skip.canSkip(method: "testItrSkippable456"))
    }
    
    static let finalTypeTags: FinalTypeTags<UnskippableTypeTaggedOverrideTests> = {
        withTagger { tagger in
            tagger.set(type: .itrSkippable, to: false)
            tagger.set(instance: .itrSkippable, to: true, method: "testItrSkippable")
            tagger.set(instance: .itrSkippable, to: false, method: "testItrSkippable456")
        }
    }()
}

class UnskippableMethodTaggedTests: XCTestCase, DDTaggedType {
    func testItrSkippable() {
        let skip = self.unskippableMethods
        XCTAssertFalse(skip.canSkip(method: "testItrSkippable"))
        XCTAssertTrue(skip.canSkip(method: "testItrSkippable123"))
        XCTAssertTrue(skip.canSkip(method: "testItrSkippable456"))
    }
    
    static func attachedTypeTags() -> DDTypeTags {
        let tagger = DDTypeTagger.forType(self)!
        tagger.set(tag: .itrSkippableInstanceMethod, toValue: false, forMember: "testItrSkippable")
        tagger.set(tag: .itrSkippableInstanceMethod, toValue: true, forMember: "testItrSkippable456")
        return tagger.tags()
    }
}
