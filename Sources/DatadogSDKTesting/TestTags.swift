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

/// Prevents Datadog quarantine and disabling from hiding a test's failure
/// (`prevent_failure_suppression` annotation). Can be declared on a suite and
/// overridden on a test, the same way as `RetriableTag`.
struct PreventFailureSuppressionTag: TestTag {
    typealias Value = Bool
}

extension TestTag where Self == PreventFailureSuppressionTag {
    static var preventFailureSuppression: Self { .init() }
}

extension TestTags {
    /// `false` excludes the test from Datadog Auto Test Retries, Early Flake Detection
    /// and Attempt to Fix. Framework-native retries are not affected.
    var isRetriable: Bool { self.get(tag: .retriable) ?? true }
    /// `true` prevents Datadog quarantine and disabling from controlling the test.
    var preventsFailureSuppression: Bool { self.get(tag: .preventFailureSuppression) ?? false }
}
