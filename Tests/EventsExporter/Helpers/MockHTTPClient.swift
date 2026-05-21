/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import Foundation
import XCTest

/// In-process `HTTPClientType` replacement used by `DataUploaderTests` and
/// `DataUploadWorkerTests`. Records every request and returns the configured
/// delivery immediately, with no dependency on `URLSession` or `URLProtocol`.
///
/// This lets the sync-via-`RunLoopWaiter` upload path that `DataUploader` uses
/// run cleanly on watchOS, where `URLSession` is documented to bypass custom
/// `URLProtocol`s for synchronous dispatch.
internal final class MockHTTPClient: HTTPClientType, @unchecked Sendable {
    enum Delivery {
        case success(response: HTTPURLResponse, data: Data = .mockAny())
        case failure(error: HTTPClient.RequestError)
    }

    private let queue: DispatchQueue
    private let delivery: Delivery

    private var recordedRequests: [URLRequest] = []
    private var pendingExpectation: XCTestExpectation?

    init(delivery: Delivery) {
        self.delivery = delivery
        self.queue = DispatchQueue(label: "com.datadoghq.MockHTTPClient-\(UUID().uuidString)")
    }

    // MARK: HTTPClientType

    func send(request: URLRequest) async throws(HTTPClient.RequestError) -> HTTPURLResponse {
        try await Task<Result<HTTPURLResponse, HTTPClient.RequestError>, Never>.detached {
            self.record(request)
            switch self.delivery {
            case .success(let response, _): return .success(response)
            case .failure(let error): return .failure(error)
            }
        }.value.get()
    }

    func sendWithResponse(request: URLRequest) async throws(HTTPClient.RequestError) -> Data {
        try await Task<Result<Data, HTTPClient.RequestError>, Never>.detached {
            self.record(request)
            switch self.delivery {
            case .success(_, let data): return .success(data)
            case .failure(let error): return .failure(error)
            }
        }.value.get()
    }

    // MARK: Test API

    /// Returns the requests captured so far without waiting.
    var requests: [URLRequest] {
        queue.sync { recordedRequests }
    }

    /// Waits until `count` requests have been recorded and returns them.
    @discardableResult
    func waitAndReturnRequests(count: UInt, timeout: TimeInterval = 6, file: StaticString = #file, line: UInt = #line) -> [URLRequest] {
        precondition(pendingExpectation == nil, "MockHTTPClient is already waiting on `waitAndReturnRequests`.")
        let expectation = XCTestExpectation(description: "Receive \(count) requests.")
        if count > 0 {
            expectation.expectedFulfillmentCount = Int(count)
        } else {
            expectation.isInverted = true
        }

        queue.sync {
            self.pendingExpectation = expectation
            self.recordedRequests.forEach { _ in expectation.fulfill() }
        }

        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        switch result {
        case .completed:
            break
        case .timedOut:
            XCTFail("Exceeded timeout of \(timeout)s with \(requests.count) of \(count) expected requests.", file: file, line: line)
            return Array(repeating: .mockAny(), count: Int(count))
        case .invertedFulfillment:
            XCTFail("\(requests.count) requests were sent, but none were expected.", file: file, line: line)
            return queue.sync { recordedRequests }
        case .incorrectOrder, .interrupted:
            fatalError("Can't happen.")
        @unknown default:
            fatalError()
        }

        return queue.sync { recordedRequests }
    }

    func waitFor(requestsCompletion count: UInt, timeout: TimeInterval = 6, file: StaticString = #file, line: UInt = #line) {
        _ = waitAndReturnRequests(count: count, timeout: timeout, file: file, line: line)
    }

    func waitAndAssertNoRequestsSent(timeout: TimeInterval = 0.5, file: StaticString = #file, line: UInt = #line) {
        waitFor(requestsCompletion: 0, timeout: timeout, file: file, line: line)
    }

    // MARK: Private

    private func record(_ request: URLRequest) {
        queue.sync {
            self.recordedRequests.append(request)
            self.pendingExpectation?.fulfill()
        }
    }
}
