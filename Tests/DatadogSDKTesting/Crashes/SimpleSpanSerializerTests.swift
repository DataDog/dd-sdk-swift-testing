/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest

internal class SimpleSpanSerializerTests: XCTestCase {
    func testGivenASimpleSpan_ItSerializesAndDeserializesWithoutChanges() throws {
        let original = SimpleSpanData(traceIdHi: 1, traceIdLo: 2, spanId: 3, name: "name", startTime: Date(timeIntervalSinceReferenceDate: 33), stringAttributes: [:])

        let serialized = SimpleSpanSerializer.serializeSpan(simpleSpan: original)
        let deserialized = SimpleSpanSerializer.deserializeSpan(data: serialized)

        XCTAssertEqual(original, deserialized)
    }

    func testGivenASpanWithAttributes_ItSerializesAndDeserializes() throws {
        let original = SimpleSpanData(traceIdHi: 1, traceIdLo: 2, spanId: 3, name: "name", startTime: Date(timeIntervalSinceReferenceDate: 33), stringAttributes: ["key1": "value1", "key2": "value2"])

        let serialized = SimpleSpanSerializer.serializeSpan(simpleSpan: original)
        let deserialized = SimpleSpanSerializer.deserializeSpan(data: serialized)

        XCTAssertEqual(original, deserialized)
    }
}
