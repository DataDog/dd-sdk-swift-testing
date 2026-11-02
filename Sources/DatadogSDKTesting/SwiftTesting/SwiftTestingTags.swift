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
        /// Prevents Datadog quarantine and disabling from hiding annotated failures.
        @Tag public static var preventFailureSuppression: Tag
        /// Allows Datadog quarantine and disabling again. Overrides `preventFailureSuppression` of the parent suite.
        @Tag public static var allowFailureSuppression: Tag
    }
}

protocol STTestTag: TestTag {
    /// `tags` are ordered by declaration: tags of the outermost suite come first,
    /// tags of the test itself come last. Parse from the end so the most specific
    /// declaration wins.
    func parse(tags: borrowing [Tag]) -> Value?
}

struct STTestTags: TestTags {
    let tags: [Tag]
    
    init(test: borrowing Testing.Test) {
        // Swift Testing prepends recursive traits of the parent suites to the test traits.
        self.tags = test.traits.flatMap { ($0 as? Tag.List)?.tags ?? [] }
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

extension Array where Element == Tag {
    /// Returns `true` for the `positive` tag, `false` for the `negative` tag
    /// and `nil` if none is declared. The last declared tag wins.
    func resolve(positive: Tag, negative: Tag) -> Bool? {
        last { $0 == positive || $0 == negative }.map { $0 == positive }
    }
}

// Retriable tag
extension RetriableTag: STTestTag {
    func parse(tags: borrowing [Tag]) -> Bool? {
        tags.resolve(positive: .dd.retriable, negative: .dd.nonretriable)
    }
}

// Prevent failure suppression tag
extension PreventFailureSuppressionTag: STTestTag {
    func parse(tags: borrowing [Tag]) -> Bool? {
        tags.resolve(positive: .dd.preventFailureSuppression, negative: .dd.allowFailureSuppression)
    }
}
#endif
