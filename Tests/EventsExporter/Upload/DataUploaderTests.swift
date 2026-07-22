/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import XCTest

extension DataUploadStatus: @retroactive Equatable {}
extension DataUploadStatus: EquatableInTests {
    public static func == (lhs: DataUploadStatus, rhs: DataUploadStatus) -> Bool {
        lhs.needsRetry == rhs.needsRetry && lhs.waitTime == rhs.waitTime
    }
}

class DataUploaderTests: XCTestCase {
    func testWhenUploadCompletesWithSuccess_itReturnsExpectedUploadStatus() {
        // Given
        let randomResponse: HTTPURLResponse = .mockResponseWith(statusCode: (100 ... 399).randomElement()!)
        let httpClient = MockHTTPClient(delivery: .success(response: randomResponse))
        let uploader = MockClosureDataUploader(httpClient: httpClient)

        // When
        let uploadStatus = uploader.upload(data: .mockAny(), timeout: 5)

        // Then
        let expectedUploadStatus = DataUploadStatus(httpResponse: randomResponse)
        XCTAssertEqual(uploadStatus, expectedUploadStatus)
        httpClient.waitFor(requestsCompletion: 1)
    }

    func testWhenUploadCompletesWithFailure_itReturnsExpectedUploadStatus() {
        // Given
        let randomErrorDescription: String = .mockRandom()
        let randomError = NSError(domain: .mockRandom(), code: .mockRandom(),
                                  userInfo: [NSLocalizedDescriptionKey: randomErrorDescription])
        let httpClient = MockHTTPClient(delivery: .failure(error: .transport(randomError)))
        let uploader = MockClosureDataUploader(httpClient: httpClient)

        // When
        let uploadStatus = uploader.upload(data: .mockAny(), timeout: 5)

        // Then
        let expectedUploadStatus = DataUploadStatus(api: .transport(randomError))
        XCTAssertEqual(uploadStatus, expectedUploadStatus)
        httpClient.waitFor(requestsCompletion: 1)
    }
}
