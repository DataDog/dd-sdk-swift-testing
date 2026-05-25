/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import XCTest

class HTTPClientTests: XCTestCase {
    @MainActor
    func testWhenRequestIsDelivered_itReturnsHTTPResponse() async throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let client = HTTPClient(session: server.getInterceptedURLSession(), debug: false)

        let httpResponse = try await client.send(request: .mockAny())
        XCTAssertEqual(httpResponse.statusCode, 200)

        server.waitFor(requestsCompletion: 1)
    }

    @MainActor
    func testWhenRequestIsNotDelivered_itReturnsHTTPRequestDeliveryError() async throws {
        // Same watchOS URLProtocol bypass as `DataUploaderTests`: the request
        // reaches the real network rather than `ServerMockProtocol`, so the
        // mocked failure is never delivered to the completion handler.
        try XCTSkipIf(isWatchOS, "watchOS URLSession bypasses URLProtocol mocks for sync dispatch")
        let mockError = NSError(domain: "network", code: 999, userInfo: [NSLocalizedDescriptionKey: "no internet connection"])
        let server = ServerMock(delivery: .failure(error: mockError))
        let client = HTTPClient(session: server.getInterceptedURLSession(), debug: false)

        do {
            _ = try await client.send(request: .mockAny())
            XCTFail("Expected transport failure")
        } catch HTTPClient.RequestError.transport(let error) {
            XCTAssertEqual((error as NSError).localizedDescription, "no internet connection")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        server.waitFor(requestsCompletion: 1)
    }
}
