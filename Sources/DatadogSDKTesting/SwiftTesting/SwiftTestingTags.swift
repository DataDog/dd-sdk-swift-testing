/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

#if canImport(Testing)
import Testing

extension Tag {
    enum dd {
        @Tag static var unretriable: Tag
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
        !tags.contains(Tag.dd.unretriable)
    }
}
#endif
