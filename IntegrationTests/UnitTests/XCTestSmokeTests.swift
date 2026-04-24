/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
import Foundation
import DatadogSDKTesting

final class XCBasicPass: XCTestCase {
    func testBasicPass() {
        XCTAssert(Bool(true))
    }
}

final class XCBasicSkip: XCTestCase {
    func testBasicSkip() throws {
        throw XCTSkip("skip")
    }
}

final class XCBasicError: XCTestCase {
    func testBasicError() {
        XCTAssert(Bool(false))
    }
}

final class XCAsynchronousPass: XCTestCase {
    func testAsynchronousPass() async throws {
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }
}

final class XCAsynchronousSkip: XCTestCase {
    func testAsynchronousSkip() async throws {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        throw XCTSkip("skip")
    }
}

final class XCAsynchronousError: XCTestCase {
    func testAsynchronousError() async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssert(Bool(false))
    }
}

final class XCBenchmark: XCTestCase {
    func testBenchmark() {
        measure {
            Thread.sleep(forTimeInterval: .random(in: 0.001...0.01))
        }
    }
}

final class XCNetworkIntegration: XCTestCase {
    func testNetworkIntegration() async throws {
        let url = URL(string: "https://github.com/DataDog/dd-sdk-swift-testing")!
        let (_, _) = try await URLSession.shared.data(from: url)
    }
}

final class XCCrash: XCTestCase {
    func testCrash() {
        let array: [Int] = [1]
        XCTAssertEqual(array[1], 1)
    }
}
