/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import XCTest

class DataUploadWorkerTests: XCTestCase {
    lazy var dateProvider = RelativeDateProvider(advancingBySeconds: 1)
    lazy var orchestrator = FilesOrchestrator(
        directory: temporaryDirectory,
        performance: StoragePerformanceMock.writeEachObjectToNewFileAndReadAllFiles,
        dateProvider: dateProvider
    )
    lazy var writer = FileWriter(
        entity: "datauploadworker",
        dataFormat: DataFormat.mockWith(prefix: "[", suffix: "]", separator: ","),
        orchestrator: orchestrator,
        encoder: JSONEncoder.apiEncoder,
        log: Log()
    )
    lazy var reader = FileReader(
        dataFormat: DataFormat.mockWith(prefix: "[", suffix: "]", separator: ","),
        orchestrator: orchestrator
    )

    override func setUp() {
        super.setUp()
        temporaryDirectory.testCreate()
    }

    override func tearDown() {
        temporaryDirectory.testDelete()
        super.tearDown()
    }

    // MARK: - Data Uploads

    func testItUploadsAllData() {
        let httpClient = MockHTTPClient(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let dataUploader = MockClosureDataUploader(httpClient: httpClient)

        // Given
        writer.write(value: ["k1": "v1"])
        writer.write(value: ["k2": "v2"])
        writer.write(value: ["k3": "v3"])

        // When
        let worker = DataUploadWorker(
            fileReader: reader,
            dataUploader: dataUploader,
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log()
        )

        // Then
        let recordedRequests = httpClient.waitAndReturnRequests(count: 3)
        XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k1":"v1"}]"#.utf8Data })
        XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k2":"v2"}]"#.utf8Data })
        XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k3":"v3"}]"#.utf8Data })

        worker.stop()

        XCTAssertEqual(try temporaryDirectory.files().count, 0)
    }

    func testGivenDataToUpload_whenUploadFinishesAndDoesNotNeedToBeRetried_thenDataIsDeleted() {
        let startUploadExpectation = self.expectation(description: "Upload has started")

        var mockDataUploader = DataUploaderMock(uploadStatus: .mockWith(needsRetry: false))
        mockDataUploader.onUpload = { startUploadExpectation.fulfill() }

        // Given
        try? writer.writeSync(value: ["key": "value"])
        XCTAssertEqual(try temporaryDirectory.files().count, 1)

        // When
        let worker = DataUploadWorker(
            fileReader: reader,
            dataUploader: mockDataUploader,
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log()
        )

        wait(for: [startUploadExpectation], timeout: 5.0)
        worker.stop()

        // Then
        XCTAssertEqual(try temporaryDirectory.files().count, 0, "When upload finishes with `needsRetry: false`, data should be deleted")
    }

    func testGivenDataToUpload_whenUploadFinishesAndNeedsToBeRetried_thenDataIsPreserved() {
        let startUploadExpectation = self.expectation(description: "Upload has started")
        // `needsRetry: true` keeps the batch on disk, so the worker re-uploads on
        // every tick. Don't fail on the (expected) second fulfillment.
        startUploadExpectation.assertForOverFulfill = false

        var mockDataUploader = DataUploaderMock(uploadStatus: .mockWith(needsRetry: true))
        mockDataUploader.onUpload = { startUploadExpectation.fulfill() }

        // Given
        try? writer.writeSync(value: ["key": "value"])
        XCTAssertEqual(try temporaryDirectory.files().count, 1)

        // When
        let worker = DataUploadWorker(
            fileReader: reader,
            dataUploader: mockDataUploader,
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log()
        )

        wait(for: [startUploadExpectation], timeout: 0.5)
        worker.stop()

        // Then
        XCTAssertEqual(try temporaryDirectory.files().count, 1, "When upload finishes with `needsRetry: true`, data should be preserved")
    }

    // MARK: - Telemetry observer

    func testItReportsUploadAttemptToObserver() {
        let attemptExpectation = expectation(description: "upload attempt reported")
        attemptExpectation.assertForOverFulfill = false
        let observer = RecordingUploadObserver { attemptExpectation.fulfill() }
        let mockDataUploader = DataUploaderMock(uploadStatus: .mockWith(needsRetry: false))

        // Given
        try? writer.writeSync(value: ["key": "value"])

        // When
        let worker = DataUploadWorker(
            fileReader: reader,
            dataUploader: mockDataUploader,
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log(),
            observer: observer
        )
        wait(for: [attemptExpectation], timeout: 5.0)
        worker.stop()

        // Then
        let attempts = observer.attempts
        XCTAssertGreaterThanOrEqual(attempts.count, 1)
        XCTAssertEqual(attempts.first?.success, true)
        XCTAssertEqual(attempts.first?.retriable, false)
        XCTAssertGreaterThan(attempts.first?.payloadBytes ?? 0, 0)
    }

    // MARK: - Upload Interval Changes

    func testWhenThereIsNoBatch_thenIntervalIncreases() {
        let delayChangeExpectation = expectation(description: "Upload delay is increased")
        let mockDelay = MockDelay { command in
            if case .increase = command {
                delayChangeExpectation.fulfill()
            } else {
                XCTFail("Wrong command is sent!")
            }
        }

        // When
        XCTAssertEqual(try temporaryDirectory.files().count, 0)

        let httpClient = MockHTTPClient(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let dataUploader = MockClosureDataUploader(httpClient: httpClient)
        let worker = DataUploadWorker(
            fileReader: reader,
            dataUploader: dataUploader,
            delay: mockDelay,
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log()
        )

        // Then
        waitForExpectations(timeout: 1, handler: nil)
        httpClient.waitAndAssertNoRequestsSent()
        worker.stop()
    }

    func testWhenBatchFails_thenIntervalIncreases() {
        let delayChangeExpectation = expectation(description: "Upload delay is increased")
        let mockDelay = MockDelay { command in
            if case .increase = command {
                delayChangeExpectation.fulfill()
            } else {
                XCTFail("Wrong command is sent!")
            }
        }

        // When
        writer.write(value: ["k1": "v1"])

        let httpClient = MockHTTPClient(delivery: .success(response: .mockResponseWith(statusCode: 500)))
        let dataUploader = MockClosureDataUploader(httpClient: httpClient)
        let worker = DataUploadWorker(
            fileReader: reader,
            dataUploader: dataUploader,
            delay: mockDelay,
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log()
        )

        // Then
        httpClient.waitFor(requestsCompletion: 1)
        waitForExpectations(timeout: 1, handler: nil)
        worker.stop()
    }

    func testWhenBatchSucceeds_thenIntervalDecreases() {
        let delayChangeExpectation = expectation(description: "Upload delay is decreased")
        let mockDelay = MockDelay { command in
            if case .decrease = command {
                delayChangeExpectation.fulfill()
            } else {
                XCTFail("Wrong command is sent!")
            }
        }

        // When
        writer.write(value: ["k1": "v1"])

        let httpClient = MockHTTPClient(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let dataUploader = MockClosureDataUploader(httpClient: httpClient)
        let worker = DataUploadWorker(
            fileReader: reader,
            dataUploader: dataUploader,
            delay: mockDelay,
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log()
        )

        // Then
        httpClient.waitFor(requestsCompletion: 1)
        waitForExpectations(timeout: 2, handler: nil)
        worker.stop()
    }

    // MARK: - Tearing Down

    func testWhenCancelled_itPerformsNoMoreUploads() {
        // Given
        let httpClient = MockHTTPClient(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let dataUploader = MockClosureDataUploader(httpClient: httpClient)
        let worker = DataUploadWorker(
            fileReader: reader,
            dataUploader: dataUploader,
            delay: MockDelay(),
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log()
        )

        // When
        worker.stop()

        // Then
        writer.write(value: ["k1": "v1"])

        httpClient.waitAndAssertNoRequestsSent()
    }

    func testItFlushesAllData() throws {
        let httpClient = MockHTTPClient(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let dataUploader = MockClosureDataUploader(httpClient: httpClient)
        let worker = DataUploadWorker(
            fileReader: reader,
            dataUploader: dataUploader,
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log()
        )

        // Given
        writer.write(value: ["k1": "v1"])
        writer.write(value: ["k2": "v2"])
        writer.write(value: ["k3": "v3"])
        writer.queue.sync {}

        // When
        _ = try worker.flush()

        // Then
        XCTAssertEqual(try temporaryDirectory.files().count, 0)

        let recordedRequests = httpClient.waitAndReturnRequests(count: 3)
        XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k1":"v1"}]"#.utf8Data })
        XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k2":"v2"}]"#.utf8Data })
        XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k3":"v3"}]"#.utf8Data })

        worker.stop()
    }

    func testFlushGivesUpAfterMaxRetriesInsteadOfHanging() throws {
        // A server that always asks to retry (e.g. persistent 503) used to make
        // `flush()` loop forever, hanging the synchronous shutdown flush.
        let uploadCount = LockedInt()
        var mockDataUploader = DataUploaderMock(uploadStatus: .mockWith(needsRetry: true))
        mockDataUploader.onUpload = { uploadCount.increment() }

        writer.write(value: ["k1": "v1"])
        writer.queue.sync {}

        let worker = DataUploadWorker(
            fileReader: reader,
            dataUploader: mockDataUploader,
            delay: MockDelay(),
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log()
        )

        // When: this must return (not hang) and report failure.
        let flushed = try worker.flush()

        // Then
        XCTAssertFalse(flushed, "A persistently-retriable upload should end in failure, not success")
        XCTAssertEqual(uploadCount.value, 4, "1 initial attempt + 3 retries, then give up")
        XCTAssertEqual(try temporaryDirectory.files().count, 1, "Undelivered batch is left on disk for a later run")

        worker.stop()
    }
}

/// Thread-safe integer counter for asserting on callbacks made from the worker queue.
private final class LockedInt: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int { lock.withLock { _value } }
    func increment() { lock.withLock { _value += 1 } }
}

struct MockDelay: Delay {
    enum Command {
        case increase, decrease
    }

    var callback: ((Command) -> Void)?
    let current: TimeInterval = 0.1

    mutating func decrease() {
        callback?(.decrease)
        callback = nil
    }

    mutating func increase() {
        callback?(.increase)
        callback = nil
    }

    mutating func set(delay: TimeInterval) -> Bool {
        // tests don't exercise server-driven retry delay; treat as "can't accept"
        // so the worker falls through to its default retry/back-off path.
        return false
    }
}

/// Records `UploadObserver` callbacks (which arrive on the worker's queue) for
/// assertions. `onAttempt` fires for each recorded attempt so tests can await it.
private final class RecordingUploadObserver: UploadObserver, @unchecked Sendable {
    typealias Attempt = (payloadBytes: Int, durationMs: Double, success: Bool, retriable: Bool)

    private let lock = NSLock()
    private var _attempts: [Attempt] = []
    private var _dropped: [Int] = []
    private let onAttempt: @Sendable () -> Void

    init(onAttempt: @escaping @Sendable () -> Void = {}) {
        self.onAttempt = onAttempt
    }

    var attempts: [Attempt] { lock.withLock { _attempts } }
    var dropped: [Int] { lock.withLock { _dropped } }

    func uploadAttempt(payloadBytes: Int, durationMs: Double, success: Bool, retriable: Bool) {
        lock.withLock { _attempts.append((payloadBytes, durationMs, success, retriable)) }
        onAttempt()
    }

    func uploadDropped(payloadBytes: Int) {
        lock.withLock { _dropped.append(payloadBytes) }
    }
}
