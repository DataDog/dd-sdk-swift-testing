/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import EventsExporter
import OpenTelemetryApi
@testable import OpenTelemetrySdk

class SpanSanitizerTests: XCTestCase {
    func testWhenAttributeNameExceeds10NestedLevels_itIsEscapedByUnderscore() {

        let spanData = SpanData(traceId: TraceId(), spanId: SpanId(), name: "spanName", kind: .client, startTime: Date(), attributes: [
            "tag-one": AttributeValue(String.mockAny())!,
            "tag-one.two": AttributeValue(String.mockAny())!,
            "tag-one.two.three": AttributeValue(String.mockAny())!,
            "tag-one.two.three.four": AttributeValue(String.mockAny())!,
            "tag-one.two.three.four.five": AttributeValue(String.mockAny())!,
            "tag-one.two.three.four.five.six": AttributeValue(String.mockAny())!,
            "tag-one.two.three.four.five.six.seven": AttributeValue(String.mockAny())!,
            "tag-one.two.three.four.five.six.seven.eight": AttributeValue(String.mockAny())!,
            "tag-one.two.three.four.five.six.seven.eight.nine": AttributeValue(String.mockAny())!,
            "tag-one.two.three.four.five.six.seven.eight.nine.ten": AttributeValue(String.mockAny())!,
            "tag-one.two.three.four.five.six.seven.eight.nine.ten.eleven": AttributeValue(String.mockAny())!,
            "tag-one.two.three.four.five.six.seven.eight.nine.ten.eleven.twelve": AttributeValue(String.mockAny())!,
        ], endTime: Date().addingTimeInterval(1.0))

        let ddSpan = DDSpan(spanData: spanData)

        // When
        let sanitized = SpanSanitizer().sanitize(span:ddSpan)
        // Then
        XCTAssertEqual(sanitized.tags.count, 12)
        XCTAssertNotNil(sanitized.tags["tag-one"])
        XCTAssertNotNil(sanitized.tags["tag-one.two"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six.seven"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six.seven.eight"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six.seven.eight.nine"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six.seven.eight.nine.ten"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six.seven.eight.nine.ten_eleven"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six.seven.eight.nine.ten_eleven_twelve"])
    }

    func testWhenTagValueExceedsMaxLength_itIsTruncated() {
        let longValue = String(repeating: "x", count: AttributesSanitizer.Constraints.maxAttributeValueLength + 100)
        let shortValue = String(repeating: "y", count: 10)

        let spanData = SpanData(traceId: TraceId(), spanId: SpanId(), name: "spanName", kind: .client, startTime: Date(), attributes: [
            "long-tag": AttributeValue(longValue)!,
            "short-tag": AttributeValue(shortValue)!,
        ], endTime: Date().addingTimeInterval(1.0))

        let ddSpan = DDSpan(spanData: spanData)

        // When
        let sanitized = SpanSanitizer().sanitize(span: ddSpan)

        // Then
        XCTAssertEqual(sanitized.tags["long-tag"]?.description.count, AttributesSanitizer.Constraints.maxAttributeValueLength)
        XCTAssertEqual(sanitized.tags["short-tag"]?.description, shortValue)
    }

    func testWhenNonStringTagValueExceedsMaxLength_itIsStringifiedAndTruncated() {
        let maxLength = AttributesSanitizer.Constraints.maxAttributeValueLength
        let longArray = Array(repeating: "item", count: maxLength)

        let spanData = SpanData(traceId: TraceId(), spanId: SpanId(), name: "spanName", kind: .client, startTime: Date(), attributes: [
            "array-tag": AttributeValue(longArray),
            "bool-tag": AttributeValue(true),
            "int-tag": AttributeValue(42),
        ], endTime: Date().addingTimeInterval(1.0))

        let ddSpan = DDSpan(spanData: spanData)

        // When
        let sanitized = SpanSanitizer().sanitize(span: ddSpan)

        // Then
        // The array is serialized to its `description` and truncated to the limit.
        if case .string(let value)? = sanitized.tags["array-tag"] {
            XCTAssertEqual(value.count, maxLength)
        } else {
            XCTFail("Expected array tag to be converted to a string")
        }
        // Booleans are stringified (short, so not truncated); numbers are left as-is.
        XCTAssertEqual(sanitized.tags["bool-tag"], .string("true"))
        XCTAssertEqual(sanitized.tags["int-tag"], .int(42))
    }

    func testWhenMetadataKeyOrValueExceedsMaxLength_itIsTruncated() {
        let longKey = String(repeating: "k", count: AttributesSanitizer.Constraints.maxAttributeValueLength + 100)
        let longValue = String(repeating: "v", count: AttributesSanitizer.Constraints.maxAttributeValueLength + 100)
        let shortValue = String(repeating: "s", count: 10)

        var metadata = SpanMetadata()
        metadata[string: longKey] = longValue
        metadata[string: "short-key"] = shortValue

        // When
        let sanitized = SpanSanitizer().sanitize(metadata: metadata).metadata[SpanMetadata.SpanType.generic.rawValue]

        // Then
        let trimmedKey = String(longKey.prefix(AttributesSanitizer.Constraints.maxAttributeValueLength))
        XCTAssertNil(sanitized?[longKey])
        XCTAssertEqual(sanitized?[trimmedKey]?.string?.count, AttributesSanitizer.Constraints.maxAttributeValueLength)
        XCTAssertEqual(sanitized?["short-key"]?.string, shortValue)
    }
}
