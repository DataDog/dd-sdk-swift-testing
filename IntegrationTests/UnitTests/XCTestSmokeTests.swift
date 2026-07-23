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

/// SDTEST-3913: reproduces an Xcode "Runtime Issue" — the Thread Performance
/// Checker's priority-inversion diagnostic — which XCTest records via
/// `XCTIssue` with `isFailure == false`. XCTest itself doesn't fail the test
/// for it, and the SDK must not either (no retry, no failed status).
final class XCRuntimeIssue: XCTestCase {
    func testPriorityInversion() {
        let lock = NSLock()
        let holderStarted = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .background).async {
            lock.lock()
            holderStarted.signal()
            Thread.sleep(forTimeInterval: 1.0)
            lock.unlock()
        }

        holderStarted.wait()
        lock.lock() // main thread (.userInteractive) blocks on a .background holder
        lock.unlock()

        XCTAssertTrue(true)
    }
}

final class XCCrash: XCTestCase {
    func testCrash() {
        let array: [Int] = [1]
        XCTAssertEqual(array[1], 1)
    }

    func testNoCrash() {
        let array: [Int] = [1]
        XCTAssertEqual(array[0], 1)
    }
}

/// Drives the consumer-facing telemetry pipelines from inside a real XCTest run
/// against the *stripped* framework (the inner targets are built
/// `-configuration Release`, so the bundled OpenTelemetry symbols are private —
/// this exercises the framework exactly as shipped). print() → StdoutCapture →
/// span event → SpanEventsLogExporterAdapter → LogsExporter; and the implicit
/// per-test code-coverage profraw → CoverageExporter → CoverageRecord upload
/// (enabled by the xctestplan + backend settings supplied by the outer
/// harness).
///
/// Note: this is a public-API consumer only. The SDK's OpenTelemetry is private
/// (stripped), so a consumer cannot share its OTel instance; the OTel-bridge is
/// intentionally not covered here.
final class XCStdoutOTelAndCoverage: XCTestCase {
    func testStdoutOTelAndCoverage() {
        // 1) stdout path
        print("hello from XCTest stdout")

        // 2) The test passing is enough to trigger DDCoverageHelper.endTest,
        //    which is what produces the coverage payload — no extra wiring.
        XCTAssert(Bool(true))
    }
}
