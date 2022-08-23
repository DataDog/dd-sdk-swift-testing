/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
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

        let ddSpan = DDSpan(spanData: spanData, serviceName: "name", applicationVersion: "1.0")

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

    func testWhenNumberOfAttributesExceedsLimit_itDropsExtraOnes() {
        let twiceTheLimit = AttributesSanitizer.Constraints.maxNumberOfAttributes * 2

        let mockTags = (0..<twiceTheLimit).map { index in
            ("tag-\(index)", AttributeValue(String.mockAny())!)
        }

        let spanData = SpanData(traceId: TraceId(), spanId: SpanId(), name: "spanName", kind: .client, startTime: Date(), attributes:Dictionary(uniqueKeysWithValues: mockTags), endTime: Date().addingTimeInterval(1.0))

        let ddSpan = DDSpan(spanData: spanData, serviceName: "name", applicationVersion: "1.0")

        // When
        let sanitized = SpanSanitizer().sanitize(span: ddSpan)

        // Then
        XCTAssertEqual(
            sanitized.tags.count,
            AttributesSanitizer.Constraints.maxNumberOfAttributes
        )
    }
}
