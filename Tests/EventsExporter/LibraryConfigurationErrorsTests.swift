/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import XCTest
import TestUtils

// MARK: - HTTPClient.RequestError.description

final class HTTPClientRequestErrorDescriptionTests: XCTestCase {
    func testHTTPWithBody() {
        let body = Data("server says no".utf8)
        let error: HTTPClient.RequestError = .http(code: 500, headers: [:], body: body)
        XCTAssertEqual("\(error)", "HTTP 500: server says no")
    }

    func testHTTPWithoutBody() {
        XCTAssertEqual("\(HTTPClient.RequestError.http(code: 401, headers: [:], body: nil))", "HTTP 401")
        XCTAssertEqual("\(HTTPClient.RequestError.http(code: 403, headers: [:], body: Data()))", "HTTP 403")
    }

    func testTransportWrapsLocalizedDescription() {
        let underlying = NSError(domain: "DDTest", code: -1,
                                 userInfo: [NSLocalizedDescriptionKey: "no internet"])
        XCTAssertEqual("\(HTTPClient.RequestError.transport(underlying))",
                       "transport error: no internet")
    }

    func testInconsistentSession() {
        XCTAssertEqual("\(HTTPClient.RequestError.inconsistentSession)",
                       "inconsistent URLSession response")
    }
}
