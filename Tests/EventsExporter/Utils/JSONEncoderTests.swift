/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import XCTest

class JSONEncoderTests: XCTestCase {
    private let jsonEncoder = JSONEncoder.default()

    func testDateEncoding() throws {
        let encodedDate = try jsonEncoder.encode(
            EncodingContainer(Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 0.123))
        )

        XCTAssertEqual(encodedDate.utf8String, #"{"value":"2019-12-15T10:00:00.123Z"}"#)
    }

    func testURLEncoding() throws {
        let encodedURL = try jsonEncoder.encode(
            EncodingContainer(URL(string: "https://example.com/foo")!)
        )

        if #available(OSX 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
            XCTAssertEqual(encodedURL.utf8String, #"{"value":"https://example.com/foo"}"#)
        } else {
            XCTAssertEqual(encodedURL.utf8String, #"{"value":"https:\/\/example.com\/foo"}"#)
        }
    }
}
