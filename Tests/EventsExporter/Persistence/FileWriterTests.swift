/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import XCTest

class FileWriterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        temporaryDirectory.testCreate()
    }

    override func tearDown() {
        temporaryDirectory.testDelete()
        super.tearDown()
    }

    func testItWritesDataToSingleFile() throws {
        let expectation = self.expectation(description: "write completed")
        let writer = FileWriter(
            entity: "testfilewriter",
            dataFormat: DataFormat(prefix: Data("[".utf8),
                                   suffix: Data("]".utf8),
                                   separator: Data(",".utf8)),
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: PerformancePreset.default,
                dateProvider: SystemDateProvider()
            ),
            encoder: JSONEncoder.apiEncoder
        )

        writer.write(value: ["key1": "value1"])
        writer.write(value: ["key2": "value3"])
        writer.write(value: ["key3": "value3"])

        waitForWritesCompletion(on: writer.queue, thenFulfill: expectation)
        waitForExpectations(timeout: 1, handler: nil)
        XCTAssertEqual(try temporaryDirectory.files().count, 1)
        XCTAssertEqual(
            try temporaryDirectory.files()[0].read(),
            #"[{"key1":"value1"},{"key2":"value3"},{"key3":"value3"}"# .utf8Data
        )
    }

    func testItReportsSerializationAndPayloadCountsToObserver() throws {
        let observer = RecordingPayloadObserver()
        let expectation = self.expectation(description: "write completed")
        let writer = FileWriter(
            entity: "testfilewriter-observer",
            dataFormat: DataFormat(prefix: Data("[".utf8),
                                   suffix: Data("]".utf8),
                                   separator: Data(",".utf8)),
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: StoragePerformanceMock.appendToOneFile,
                dateProvider: SystemDateProvider()
            ),
            encoder: JSONEncoder.apiEncoder,
            observer: observer
        )

        writer.write(value: ["key1": "value1"])
        writer.write(value: ["key2": "value2"])
        writer.write(value: ["key3": "value3"])

        waitForWritesCompletion(on: writer.queue, thenFulfill: expectation)
        waitForExpectations(timeout: 1, handler: nil)

        // Nothing finalized while the file is open.
        XCTAssertEqual(observer.finalized.count, 0)

        // Closing the file finalizes it with the full event count and the summed
        // serialization time of those events.
        writer.closeCurrentFile()
        XCTAssertEqual(observer.finalized.map(\.eventCount), [3])
        XCTAssertEqual(observer.finalized.first?.serializationMs ?? -1 >= 0, true)
    }

    func testGivenErrorVerbosity_whenIndividualDataExceedsMaxWriteSize_itDropsDataAndPrintsError() throws {
        let expectation1 = self.expectation(description: "write completed")
        let expectation2 = self.expectation(description: "second write completed")

        let writer = FileWriter(
            entity: "testfilewriter",
            dataFormat: DataFormat.mockWith(prefix: "[", suffix: "]"),
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: StoragePerformanceMock(
                    maxFileSize: .max,
                    maxDirectorySize: .max,
                    maxFileAgeForWrite: .distantFuture,
                    minFileAgeForRead: .mockAny(),
                    maxFileAgeForRead: .mockAny(),
                    maxObjectsInFile: .max,
                    maxObjectSize: 17, // 17 bytes is enough to write {"key1":"value1"} JSON
                    synchronousWrite: true
                ),
                dateProvider: SystemDateProvider()
            ),
            encoder: JSONEncoder.apiEncoder
        )

        writer.write(value: ["key1": "value1"]) // will be written

        waitForWritesCompletion(on: writer.queue, thenFulfill: expectation1)
        wait(for: [expectation1], timeout: 1)
        XCTAssertEqual(try temporaryDirectory.files()[0].read(), #"[{"key1":"value1"}"# .utf8Data)

        writer.write(value: ["key2": "value3 that makes it exceed 17 bytes"]) // will be dropped

        waitForWritesCompletion(on: writer.queue, thenFulfill: expectation2)
        wait(for: [expectation2], timeout: 1)
        XCTAssertEqual(try temporaryDirectory.files()[0].read(), #"[{"key1":"value1"}"# .utf8Data) // same content as before
    }

    /// NOTE: Test added after incident-4797
    func testWhenIOExceptionsHappenRandomly_theFileIsNeverMalformed() throws {
        // test doesn't work properly on the github runner.
        // global queue can stuck for couple of minutes
        // seems as some bug of virtualization
        try XCTSkipIf(isGithub)

        let expectation = self.expectation(description: "write completed")
        let writer = FileWriter(
            entity: "testfilewriter",
            dataFormat: DataFormat(prefix: Data("[".utf8),
                                   suffix: Data("]".utf8),
                                   separator: Data(",".utf8)),
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: StoragePerformanceMock(
                    maxFileSize: .max,
                    maxDirectorySize: .max,
                    maxFileAgeForWrite: .distantFuture, // write to single file
                    minFileAgeForRead: .distantFuture,
                    maxFileAgeForRead: .distantFuture,
                    maxObjectsInFile: .max, // write to single file
                    maxObjectSize: .max,
                    synchronousWrite: true
                ),
                dateProvider: SystemDateProvider()
            ),
            encoder: JSONEncoder.apiEncoder
        )

        let ioInterruptionQueue = DispatchQueue(
            label: "com.datadohq.file-writer-random-io",
            target: .global(qos: writer.queue.qos.qosClass)
        )

        func randomlyInterruptIO(for file: File?) {
            ioInterruptionQueue.async {
                try? file?.makeReadonly()
                usleep(300)
                try? file?.makeReadWrite()
            }
        }

        struct Foo: Codable {
            var foo = "bar"
        }

        // Write 300 of `Foo`s and interrupt writes randomly
        try (0..<300).forEach { _ in
            writer.write(value: Foo())
            randomlyInterruptIO(for: try temporaryDirectory.files().first)
        }

        ioInterruptionQueue.sync {}
        waitForWritesCompletion(on: writer.queue, thenFulfill: expectation)
        waitForExpectations(timeout: 20, handler: nil)
        XCTAssertEqual(try temporaryDirectory.files().count, 1)

        let fileData = try temporaryDirectory.files().first!.read()
        let jsonDecoder = JSONDecoder()

        // The writer prepends `[` to the first entry and `,` between subsequent
        // entries. We close the array ourselves before decoding.
        let writtenData = try jsonDecoder.decode([Foo].self, from: fileData + "]".utf8Data)
        // Assert that some (including all) `Foo`s were written
        XCTAssertGreaterThan(writtenData.count, 0)
        XCTAssertLessThanOrEqual(writtenData.count, 300)
    }

    private func waitForWritesCompletion(on queue: DispatchQueue, thenFulfill expectation: XCTestExpectation) {
        queue.async { expectation.fulfill() }
    }

    private var isGithub: Bool {
        ProcessInfo.processInfo.environment["GITHUB_ACTION"] ?? "" != "" ||
        ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] ?? "" != ""
    }
}

/// Records `PayloadObserver` callbacks for assertions. Callbacks arrive on the
/// writer's serial queue; a lock keeps reads from the test thread safe.
private final class RecordingPayloadObserver: PayloadObserver, @unchecked Sendable {
    private let lock = NSLock()
    private var _finalized: [(eventCount: Int, serializationMs: Double)] = []
    private(set) var enqueuedCount: Int = 0

    var finalized: [(eventCount: Int, serializationMs: Double)] { lock.withLock { _finalized } }

    func eventEnqueued() {
        lock.withLock { enqueuedCount += 1 }
    }

    func payloadFinalized(eventCount: Int, serializationMs: Double) {
        lock.withLock { _finalized.append((eventCount, serializationMs)) }
    }
}
