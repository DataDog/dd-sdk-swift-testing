/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import XCTest

class JSONEncoderTests: XCTestCase {
    private let jsonEncoder = JSONEncoder.apiEncoder

    func testDateEncoding() throws {
        let encodedDate = try jsonEncoder.encode(
            Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 0.123)
        )
        XCTAssertEqual(encodedDate.utf8String, #""2019-12-15T10:00:00.123Z""#)
    }

    func testURLEncoding() throws {
        let encodedURL = try jsonEncoder.encode(
            URL(string: "https://example.com/foo")!
        )
        XCTAssertEqual(encodedURL.utf8String, #""https://example.com/foo""#)
    }
}
