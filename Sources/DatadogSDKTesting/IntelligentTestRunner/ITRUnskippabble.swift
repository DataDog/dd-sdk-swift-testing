/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import XCTest

@objc public protocol ITRUnskippabble {
    @objc optional static var itrNeverSkipTests: [String] { get }
}

extension ITRUnskippabble {
    var itrNeverSkipTests: [String]? { type(of: self).itrNeverSkipTests }
}

@objc public extension NSObject {
    @objc static var allTestNames: [String] {
        getTestNames(for: self)
    }
}

private func getTestNames(for type: AnyClass) -> [String] {
    var count: Int32 = 0
    guard let methods = class_copyMethodList(type, &count) else {
        return []
    }
    defer { free(methods) }
    return (0 ..< Int(count)).compactMap {
        String(cString: sel_getName(method_getName(methods[$0])))
    }.filter { $0.hasPrefix("test") && !$0.hasSuffix(":") }
}
