/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting
@testable import EventsExporter

final class TimeTableDedupTests: XCTestCase {
    /// Verify that the refactored `repeats(for:)` (which now delegates to
    /// `retries(forDuration:)` → `retryBucketIndex(forDuration:)`) produces the
    /// same results as the original inline ladder for all bucket boundaries.
    func testRepeatsForDurationMatchesExpectedBuckets() {
        let table = TracerSettings.EFD.TimeTable(attrs: ["5s": 10, "30s": 5, "1m": 2, "5m": 1])
        // times sorted: [(5, 10), (30, 5), (60, 2), (300, 1)]

        // Below first boundary (5s) → 10 retries
        XCTAssertEqual(table.repeats(for: 0), 10)
        XCTAssertEqual(table.repeats(for: 1), 10)
        XCTAssertEqual(table.repeats(for: 5), 10)

        // After 5s and through 30s → 10; at 30s the next bucket begins.
        XCTAssertEqual(table.repeats(for: 6), 10)
        XCTAssertEqual(table.repeats(for: 29), 10)
        XCTAssertEqual(table.repeats(for: 30), 5)

        // After 30s and through 60s → 5; at 60s the next bucket begins.
        XCTAssertEqual(table.repeats(for: 31), 5)
        XCTAssertEqual(table.repeats(for: 59), 5)
        XCTAssertEqual(table.repeats(for: 60), 2)

        // After 60s and through 300s → 2; at 300s the final configured bucket begins.
        XCTAssertEqual(table.repeats(for: 61), 2)
        XCTAssertEqual(table.repeats(for: 299), 2)
        XCTAssertEqual(table.repeats(for: 300), 1)

        // Above 300s → 0
        XCTAssertEqual(table.repeats(for: 301), 0)
        XCTAssertEqual(table.repeats(for: 700), 0)
    }

    func testRetryBucketIndexForDuration() {
        let table = TracerSettings.EFD.TimeTable(attrs: ["5s": 10, "30s": 5, "1m": 2, "5m": 1])
        // times sorted: [(5, 10), (30, 5), (60, 2), (300, 1)]

        XCTAssertEqual(table.retryBucketIndex(forDuration: 0), 0)
        XCTAssertEqual(table.retryBucketIndex(forDuration: 5), 0)
        XCTAssertEqual(table.retryBucketIndex(forDuration: 6), 0)
        XCTAssertEqual(table.retryBucketIndex(forDuration: 30), 1)
        XCTAssertEqual(table.retryBucketIndex(forDuration: 31), 1)
        XCTAssertEqual(table.retryBucketIndex(forDuration: 60), 2)
        XCTAssertEqual(table.retryBucketIndex(forDuration: 61), 2)
        XCTAssertEqual(table.retryBucketIndex(forDuration: 300), 3)
        XCTAssertEqual(table.retryBucketIndex(forDuration: 301), 4)
        XCTAssertEqual(table.retryBucketIndex(forDuration: 700), 4) // times.count = 4
    }

    func testRetriesForDurationMatchesRepeats() {
        let table = TracerSettings.EFD.TimeTable(attrs: ["5s": 10, "30s": 5, "1m": 2, "5m": 1])

        for duration in stride(from: 0.0, through: 800.0, by: 7.3) {
            XCTAssertEqual(table.retries(forDuration: duration), table.repeats(for: duration),
                           "mismatch at duration \(duration)")
        }
    }
}
