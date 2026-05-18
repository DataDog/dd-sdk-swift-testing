/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import XCTest

class FileReaderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        temporaryDirectory.testCreate()
    }

    override func tearDown() {
        temporaryDirectory.testDelete()
        super.tearDown()
    }

    func testItReadsSingleBatch() throws {
        let dataFormat = DataFormat.mockWith(prefix: "[", suffix: "]")
        let reader = FileReader(
            dataFormat: dataFormat,
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: StoragePerformanceMock.readAllFiles,
                dateProvider: SystemDateProvider()
            )
        )
        _ = try temporaryDirectory
            .createFile(named: Date.mockAny().toFileName)
            .append(data: dataFormat.formatFileContents(["ABCD".utf8Data]))

        XCTAssertEqual(try temporaryDirectory.files().count, 1)
        let batch = try reader.getNextBatch()

        XCTAssertEqual(batch?.data, "[ABCD]".utf8Data)
    }

    func testItMarksBatchesAsRead() throws {
        let dateProvider = RelativeDateProvider(advancingBySeconds: 60)
        let dataFormat = DataFormat.mockWith(prefix: "[", suffix: "]")
        let reader = FileReader(
            dataFormat: dataFormat,
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: StoragePerformanceMock.readAllFiles,
                dateProvider: dateProvider
            )
        )
        let file1 = try temporaryDirectory.createFile(named: dateProvider.currentDate().toFileName)
        try file1.append(data: dataFormat.formatFileContents(["1".utf8Data]))

        let file2 = try temporaryDirectory.createFile(named: dateProvider.currentDate().toFileName)
        try file2.append(data: dataFormat.formatFileContents(["2".utf8Data]))

        let file3 = try temporaryDirectory.createFile(named: dateProvider.currentDate().toFileName)
        try file3.append(data: dataFormat.formatFileContents(["3".utf8Data]))

        var batch: Batch
        batch = try reader.getNextBatch().unwrapOrThrow()
        XCTAssertEqual(batch.data, "[1]".utf8Data)
        try reader.markBatchAsRead(batch)

        batch = try reader.getNextBatch().unwrapOrThrow()
        XCTAssertEqual(batch.data, "[2]".utf8Data)
        try reader.markBatchAsRead(batch)

        batch = try reader.getNextBatch().unwrapOrThrow()
        XCTAssertEqual(batch.data, "[3]".utf8Data)
        try reader.markBatchAsRead(batch)

        XCTAssertNil(try reader.getNextBatch())
        XCTAssertEqual(try temporaryDirectory.files().count, 0)
    }
}
