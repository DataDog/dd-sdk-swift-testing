/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

protocol TestTag {
    associatedtype Value
}

protocol TestTags: Sendable {
    func get<T: TestTag>(tag: T) -> T.Value?
}

struct RetriableTag: TestTag {
    typealias Value = Bool
}

extension TestTag where Self == RetriableTag {
    static var retriable: Self { .init() }
}

/// A declaration excludes Datadog retries without changing framework-native retries.
struct NoAutoRetryTag: TestTag {
    typealias Value = Bool
}

/// A declaration prevents Datadog quarantine and disabling from hiding a failure.
struct PreventFailureSuppressionTag: TestTag {
    typealias Value = Bool
}

extension TestTag where Self == NoAutoRetryTag {
    static var noAutoRetry: Self { .init() }
}

extension TestTag where Self == PreventFailureSuppressionTag {
    static var preventFailureSuppression: Self { .init() }
}

extension TestTags {
    var excludesAutomaticRetries: Bool { self.get(tag: .noAutoRetry) == true }
    var preventsFailureSuppression: Bool { self.get(tag: .preventFailureSuppression) == true }
}
