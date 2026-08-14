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
            uploadTimeout: 5,
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
            uploadTimeout: 5,
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
            uploadTimeout: 5,
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log()
        )

        wait(for: [startUploadExpectation], timeout: 5.0)
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
            uploadTimeout: 5,
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
            uploadTimeout: 5,
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
            uploadTimeout: 5,
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
            uploadTimeout: 5,
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
            uploadTimeout: 5,
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
            // `flush(timeout: nil)` uses this as a real wall-clock budget for the
            // whole drain. The uploads here are instant (in-memory mock), so the
            // only thing that consumes the budget is the machine itself: on a
            // heavily loaded CI simulator the previous 5s expired mid-drain and
            // `flush` gave up with batches still on disk (flaky `2 != 0`). This
            // test asserts *all* data is flushed, so give it a budget CI load
            // can't exhaust — the give-up-on-timeout path is covered separately
            // by `testFlushGivesUpAfterTimeoutInsteadOfHanging`.
            uploadTimeout: 60,
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log()
        )
        // Stop the periodic worker up front so `flush()` is the sole uploader.
        // Otherwise its background tick races the flush on the shared queue and
        // occasionally leaves a batch behind (flaky `1 != 0`). This also mirrors
        // the production shutdown order (`Feature.stop()`: stop, then final flush)
        // and guarantees the worker is torn down even if an assertion below fails.
        worker.stop()

        // Given
        writer.write(value: ["k1": "v1"])
        writer.write(value: ["k2": "v2"])
        writer.write(value: ["k3": "v3"])
        writer.queue.sync {}

        // When
        _ = try worker.flush(timeout: nil)

        // Then
        XCTAssertEqual(try temporaryDirectory.files().count, 0)

        let recordedRequests = httpClient.waitAndReturnRequests(count: 3)
        XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k1":"v1"}]"#.utf8Data })
        XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k2":"v2"}]"#.utf8Data })
        XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k3":"v3"}]"#.utf8Data })
    }

    func testFlushGivesUpAfterTimeoutInsteadOfHanging() throws {
        // A server that always asks to retry (e.g. persistent 503) used to make
        // `flush()` loop forever, hanging the synchronous shutdown flush. It must
        // now give up once the flush timeout budget elapses.
        let uploadCount = LockedInt()
        var mockDataUploader = DataUploaderMock(uploadStatus: .mockWith(needsRetry: true))
        mockDataUploader.onUpload = { uploadCount.increment() }

        writer.write(value: ["k1": "v1"])
        writer.queue.sync {}

        let worker = DataUploadWorker(
            fileReader: reader,
            dataUploader: mockDataUploader,
            delay: MockDelay(),
            uploadTimeout: 5,
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log()
        )

        // Mirror the production shutdown order (`Feature.stop()`): stop the
        // periodic worker first so its background tick can't run a read+upload
        // cycle alongside the flush, leaving `flush()` as the only thing that
        // uploads the batch. Without this, the scheduled tick fires right after
        // flush releases the queue and adds a stray 5th upload.
        worker.stop()

        // When: this must return (not hang) once the flush timeout budget elapses.
        let flushed = try worker.flush(timeout: 0.3)

        // Then
        XCTAssertFalse(flushed, "A persistently-retriable upload should end in failure, not success")
        XCTAssertGreaterThanOrEqual(uploadCount.value, 1, "flush should attempt at least once before giving up")
        XCTAssertEqual(try temporaryDirectory.files().count, 1, "Undelivered batch is left on disk for a later run")
    }

    // MARK: - Async flush / stop

    func testAsyncFlushUploadsAllData() async throws {
        let httpClient = MockHTTPClient(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let dataUploader = MockClosureDataUploader(httpClient: httpClient)
        let worker = DataUploadWorker(
            fileReader: reader,
            dataUploader: dataUploader,
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            uploadTimeout: 60,
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log()
        )
        // Leave the async flush as the sole uploader, mirroring the shutdown order.
        await worker.stop()

        // Given
        writer.write(value: ["k1": "v1"])
        writer.write(value: ["k2": "v2"])
        writer.queue.sync {}

        // When
        let flushed = try await worker.flush(timeout: nil)

        // Then
        XCTAssertTrue(flushed)
        XCTAssertEqual(try temporaryDirectory.files().count, 0)
        let requests = httpClient.waitAndReturnRequests(count: 2)
        XCTAssertTrue(requests.contains { $0.httpBody == #"[{"k1":"v1"}]"#.utf8Data })
        XCTAssertTrue(requests.contains { $0.httpBody == #"[{"k2":"v2"}]"#.utf8Data })
    }

    func testAsyncFlushGivesUpAfterTimeoutInsteadOfHanging() async throws {
        let uploadCount = LockedInt()
        var mockDataUploader = DataUploaderMock(uploadStatus: .mockWith(needsRetry: true))
        mockDataUploader.onUpload = { uploadCount.increment() }

        writer.write(value: ["k1": "v1"])
        writer.queue.sync {}

        let worker = DataUploadWorker(
            fileReader: reader,
            dataUploader: mockDataUploader,
            delay: MockDelay(),
            uploadTimeout: 5,
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log()
        )
        await worker.stop()

        // When: a persistently-retriable upload must not loop forever.
        let flushed = try await worker.flush(timeout: 0.3)

        // Then
        XCTAssertFalse(flushed)
        XCTAssertGreaterThanOrEqual(uploadCount.value, 1)
        XCTAssertEqual(try temporaryDirectory.files().count, 1, "Undelivered batch is left on disk for a later run")
    }

    // MARK: - Flush vs. in-flight upload

    func testFlushDoesNotReportSuccessWhileABatchIsInFlight() throws {
        // A periodic upload that has already read a batch is holding its fate
        // undecided: the file is still on disk, but may be deleted at any moment.
        // A flush must wait for it rather than walk past it and claim success —
        // otherwise shutdown returns while an upload is still running, and the
        // process can exit mid-request or re-send a batch the server already took.
        let uploadStarted = expectation(description: "periodic upload started")
        uploadStarted.assertForOverFulfill = false
        let releaseUpload = DispatchSemaphore(value: 0)
        var mockDataUploader = DataUploaderMock(uploadStatus: .mockWith(needsRetry: false))
        mockDataUploader.onUpload = {
            uploadStarted.fulfill()
            // Hold the batch in flight until the assertions below have run.
            _ = releaseUpload.wait(timeout: .now() + 10)
        }

        try writer.writeSync(value: ["k1": "v1"])

        let worker = DataUploadWorker(
            fileReader: reader,
            dataUploader: mockDataUploader,
            delay: MockDelay(),
            uploadTimeout: 5,
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log()
        )
        defer {
            releaseUpload.signal()
            worker.stop()
        }
        wait(for: [uploadStarted], timeout: 5)

        // When: flushing while that upload is stuck mid-request
        let flushed = try worker.flush(timeout: 0.3)

        // Then: it must report failure, not success over an unsettled batch
        XCTAssertFalse(flushed, "flush must not report success while a batch is still in flight")
    }

    func testLastChanceFlushUploadsEvenWhileABatchIsInFlight() throws {
        // Shutdown counterpart of the test above. Anything still on disk when the
        // process exits is usually gone for good, so when the loop is wedged the
        // shutdown drain re-sends rather than giving up — even though the wedged
        // upload may already have reached the server.
        let uploadStarted = expectation(description: "periodic upload started")
        uploadStarted.assertForOverFulfill = false
        let releaseUpload = DispatchSemaphore(value: 0)
        let uploads = LockedInt()
        var mockDataUploader = DataUploaderMock(uploadStatus: .mockWith(needsRetry: false))
        mockDataUploader.onUpload = { [uploads] in
            if uploads.value == 0 {
                uploads.increment()
                uploadStarted.fulfill()
                _ = releaseUpload.wait(timeout: .now() + 10)   // wedge the first upload
            } else {
                uploads.increment()
            }
        }

        try writer.writeSync(value: ["k1": "v1"])

        let worker = DataUploadWorker(
            fileReader: reader,
            dataUploader: mockDataUploader,
            delay: MockDelay(),
            uploadTimeout: 5,
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log()
        )
        defer {
            // Release the wedged upload before stopping, or `stop()` sits waiting
            // for it — and leaving the worker running would let it consume batches
            // written by later tests.
            releaseUpload.signal()
            worker.stop()
        }
        wait(for: [uploadStarted], timeout: 5)

        // When
        let flushed = try worker.flush(timeout: 0.3, lastChance: true)

        // Then: the batch went out a second time rather than being abandoned
        XCTAssertTrue(flushed, "the last-chance drain must send what is left on disk")
        XCTAssertEqual(uploads.value, 2, "the wedged batch is re-sent instead of dropped")
    }

    func testStopWaitsForTheInFlightUploadToSettle() throws {
        // `stop()` is followed by a final flush on the shutdown path, so it has to
        // leave the storage settled: no upload still deciding whether its file
        // stays on disk.
        let uploadStarted = expectation(description: "periodic upload started")
        uploadStarted.assertForOverFulfill = false
        let uploadFinished = LockedInt()
        var mockDataUploader = DataUploaderMock(uploadStatus: .mockWith(needsRetry: false))
        mockDataUploader.onUpload = {
            uploadStarted.fulfill()
            Thread.sleep(forTimeInterval: 0.3)
            uploadFinished.increment()
        }

        try writer.writeSync(value: ["k1": "v1"])

        let worker = DataUploadWorker(
            fileReader: reader,
            dataUploader: mockDataUploader,
            delay: MockDelay(),
            uploadTimeout: 5,
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log()
        )
        wait(for: [uploadStarted], timeout: 5)

        // When
        worker.stop()

        // Then: the in-flight cycle ran to completion before stop() returned
        XCTAssertEqual(uploadFinished.value, 1, "stop() must wait for the in-flight upload to settle")
        XCTAssertEqual(try temporaryDirectory.files().count, 0, "the uploaded batch was deleted before stop() returned")
    }

    // MARK: - Disk-only persistence

    func testPersistToDiskDrainsWriterWithoutUploading() throws {
        let uploader = SpyUploadWorker()
        let store = FeatureStoreAndUpload(uploader: uploader, writer: writer)

        // Given: an event handed to the writer (queued, not necessarily written yet)
        store.write(value: ["k1": "v1"])

        // When
        store.persistToDisk()

        // Then: the write is drained onto disk, but nothing is uploaded — this is
        // what the crash handler relies on.
        XCTAssertEqual(try temporaryDirectory.files().count, 1)
        XCTAssertEqual(uploader.flushCount.value, 0, "persistToDisk must never upload")
    }

    func testAsyncStopPerformsNoMoreUploads() async {
        let httpClient = MockHTTPClient(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let dataUploader = MockClosureDataUploader(httpClient: httpClient)
        let worker = DataUploadWorker(
            fileReader: reader,
            dataUploader: dataUploader,
            delay: MockDelay(),
            uploadTimeout: 5,
            featureName: .mockAny(),
            priority: .userInteractive,
            log: Log()
        )

        // When: unlike the sync variant, this awaits the periodic task's exit.
        await worker.stop()

        // Then
        writer.write(value: ["k1": "v1"])
        httpClient.waitAndAssertNoRequestsSent()
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

/// Records whether the store asked for an upload, so disk-only paths can assert
/// that they never do.
private final class SpyUploadWorker: DataUploadWorkerType {
    let flushCount = LockedInt()

    func update(dataFormat: DataFormatType) {}

    func flush(timeout: TimeInterval?, lastChance: Bool) throws -> Bool {
        flushCount.increment()
        return true
    }

    func flush(timeout: TimeInterval?) async throws -> Bool {
        flushCount.increment()
        return true
    }

    func stop() {}
    func stop() async {}
}
