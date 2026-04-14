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
