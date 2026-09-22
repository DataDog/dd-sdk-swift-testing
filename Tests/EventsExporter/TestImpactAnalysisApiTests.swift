/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import XCTest

class TestImpactAnalysisApiTests: XCTestCase {
    /// The `citestcov` intake rejects the upload with HTTP 400 ("File event not found in the request")
    /// unless both multipart parts are sent as files, i.e. carry a `filename=` attribute.
    func testUploadCoverage_sendsCoverageAndEventAsFileParts() throws {
        let httpClient = MockHTTPClient(delivery: .success(response: .mockResponseWith(statusCode: 202)))
        let api = TestImpactAnalysisApiService(config: APIServiceConfig.mock(),
                                               httpClient: httpClient,
                                               log: Log())

        try api.uploadCoverage(batch: Data(#"{"version":2,"coverages":[]}"#.utf8),
                               observer: nil, timeout: nil)

        let request = try XCTUnwrap(httpClient.requests.first)
        XCTAssertEqual(request.url, Endpoint.us1.coverageURL)
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))

        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(body.contains(#"Content-Disposition: form-data; name="coverage"; filename="coverage.json""#),
                      "coverage part must be a file part:\n\(body)")
        XCTAssertTrue(body.contains(#"Content-Disposition: form-data; name="event"; filename="event.json""#),
                      "event part must be a file part:\n\(body)")
    }
}
