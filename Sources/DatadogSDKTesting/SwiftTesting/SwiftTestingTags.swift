/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

#if canImport(Testing)
import Testing

public extension Tag {
    enum dd {
        @Tag public static var retriable: Tag
        @Tag public static var nonretriable: Tag
        /// Excludes annotated tests from Datadog retries; native retries remain available.
        @Tag public static var noAutoRetry: Tag
        /// Prevents Datadog quarantine and disabling from hiding annotated failures.
        @Tag public static var preventFailureSuppression: Tag
    }
}

protocol STTestTag: TestTag {
    func parse(tags: borrowing Set<Tag>) -> Value?
}

struct STTestTags: TestTags {
    let tags: Set<Tag>
    
    init(test: borrowing Testing.Test) {
        self.tags = test.tags
    }
    
    func get<T: TestTag>(tag: T) -> T.Value? {
        guard let tag = tag as? any STTestTag else {
            return nil
        }
        // have to cast because normal types work from macOS 13 only
        return tag.parse(tags: tags) as! T.Value?
    }
}

extension Testing.Test {
    var attachedTags: STTestTags { .init(test: self) }
}

// Retriable tag
extension RetriableTag: STTestTag {
    func parse(tags: borrowing Set<Tag>) -> Bool? {
        if tags.contains(.dd.retriable) {
            return true
        }
        if tags.contains(.dd.nonretriable) {
            return false
        }
        return nil
    }
}

extension NoAutoRetryTag: STTestTag {
    func parse(tags: borrowing Set<Tag>) -> Bool? {
        tags.contains(.dd.noAutoRetry) ? true : nil
    }
}

extension PreventFailureSuppressionTag: STTestTag {
    func parse(tags: borrowing Set<Tag>) -> Bool? {
        tags.contains(.dd.preventFailureSuppression) ? true : nil
    }
}
#endif
