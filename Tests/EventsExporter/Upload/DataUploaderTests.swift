/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import XCTest

extension DataUploadStatus: EquatableInTests {}

class DataUploaderTests: XCTestCase {
    func testWhenUploadCompletesWithSuccess_itReturnsExpectedUploadStatus() {
        // Given
        let randomResponse: HTTPURLResponse = .mockResponseWith(statusCode: (100 ... 599).randomElement()!)

        let server = ServerMock(delivery: .success(response: randomResponse))
        let uploader = DataUploader(
            httpClient: HTTPClient(session: server.getInterceptedURLSession()),
            requestBuilder: SingleRequestBuilder.mockWith(headers: [])
        )

        // When
        let uploadStatus = uploader.upload(data: .mockAny())

        // Then
        let expectedUploadStatus = DataUploadStatus(httpResponse: randomResponse)

        XCTAssertEqual(uploadStatus, expectedUploadStatus)
        server.waitFor(requestsCompletion: 1)
    }

    func testWhenUploadCompletesWithFailure_itReturnsExpectedUploadStatus() {
        // Given
        let randomErrorDescription: String = .mockRandom()
        let randomError = NSError(domain: .mockRandom(), code: .mockRandom(), userInfo: [NSLocalizedDescriptionKey: randomErrorDescription])

        let server = ServerMock(delivery: .failure(error: randomError))
        let uploader = DataUploader(
            httpClient: HTTPClient(session: server.getInterceptedURLSession()),
            requestBuilder: SingleRequestBuilder.mockAny()
        )

        // When
        let uploadStatus = uploader.upload(data: .mockAny())

        // Then
        let expectedUploadStatus = DataUploadStatus(networkError: randomError)

        XCTAssertEqual(uploadStatus, expectedUploadStatus)
        server.waitFor(requestsCompletion: 1)
    }
}
