/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import XCTest

class FilesOrchestratorTests: XCTestCase {
    private let performance: PerformancePreset = .default

    override func setUp() {
        super.setUp()
        temporaryDirectory.testCreate()
    }

    override func tearDown() {
        temporaryDirectory.testDelete()
        super.tearDown()
    }

    /// Configures `FilesOrchestrator` under tests.
    private func configureOrchestrator(using dateProvider: DateProvider) -> FilesOrchestrator {
        return FilesOrchestrator(
            directory: temporaryDirectory,
            performance: performance,
            dateProvider: dateProvider
        )
    }

    /// Test-only adapter that pulls the chosen `WritableFile` out of
    /// `withWritableFile(...)`'s scope so existing single-threaded tests can
    /// keep using a `getWritableFile`-style call.
    private func obtainWritableFile(_ orchestrator: FilesOrchestratorType,
                                    writeSize: UInt64) throws -> WritableFile
    {
        var captured: WritableFile!
        try orchestrator.withWritableFile(writeSize: writeSize) { file, _ in
            captured = file
        }
        return captured
    }

    // MARK: - Writable file tests

    func testGivenDefaultWriteConditions_whenUsedFirstTime_itCreatesNewWritableFile() throws {
        let dateProvider = RelativeDateProvider()
        let orchestrator = configureOrchestrator(using: dateProvider)
        _ = try obtainWritableFile(orchestrator, writeSize: 1)

        XCTAssertEqual(try temporaryDirectory.files().count, 1)
        XCTAssertNotNil(try? temporaryDirectory.file(named: dateProvider.currentDate().toFileName))
    }

    func testGivenDefaultWriteConditions_whenUsedNextTime_itReusesWritableFile() throws {
        let orchestrator = configureOrchestrator(using: RelativeDateProvider(advancingBySeconds: 1))
        let file1 = try obtainWritableFile(orchestrator, writeSize: 1)
        let file2 = try obtainWritableFile(orchestrator, writeSize: 1)

        XCTAssertEqual(try temporaryDirectory.files().count, 1)
        XCTAssertEqual(file1.name, file2.name)
    }

    func testGivenDefaultWriteConditions_whenFileCanNotBeUsedMoreTimes_itCreatesNewFile() throws {
        let orchestrator = configureOrchestrator(using: RelativeDateProvider(advancingBySeconds: 0.001))
        var previousFile: WritableFile = try obtainWritableFile(orchestrator, writeSize: 1)
        var nextFile: WritableFile

        for _ in (0..<performance.maxObjectsInFile).dropLast() {
            nextFile = try obtainWritableFile(orchestrator, writeSize: 1)
            XCTAssertEqual(nextFile.name, previousFile.name)
            previousFile = nextFile
        }

        nextFile = try obtainWritableFile(orchestrator, writeSize: 1)
        XCTAssertNotEqual(nextFile.name, previousFile.name)
    }

    func testGivenDefaultWriteConditions_whenFileHasNoRoomForMore_itCreatesNewFile() throws {
        let orchestrator = configureOrchestrator(using: RelativeDateProvider(advancingBySeconds: 1))
        let chunkedData: [Data] = .mockChunksOf(
            totalSize: performance.maxFileSize,
            maxChunkSize: performance.maxObjectSize
        )

        let file1 = try obtainWritableFile(orchestrator, writeSize: performance.maxObjectSize)
        try chunkedData.forEach { chunk in try file1.append(data: chunk, synchronized: false) }
        let file2 = try obtainWritableFile(orchestrator, writeSize: 1)

        XCTAssertNotEqual(file1.name, file2.name)
    }

    func testGivenDefaultWriteConditions_fileIsNotRecentEnough_itCreatesNewFile() throws {
        let dateProvider = RelativeDateProvider()
        let orchestrator = configureOrchestrator(using: dateProvider)

        let file1 = try obtainWritableFile(orchestrator, writeSize: 1)
        dateProvider.advance(bySeconds: 1 + performance.maxFileAgeForWrite)
        let file2 = try obtainWritableFile(orchestrator, writeSize: 1)

        XCTAssertNotEqual(file1.name, file2.name)
    }

    func testWhenCurrentWritableFileIsDeleted_itCreatesNewOne() throws {
        let orchestrator = configureOrchestrator(using: RelativeDateProvider(advancingBySeconds: 1))

        let file1 = try obtainWritableFile(orchestrator, writeSize: 1)
        try temporaryDirectory.files().forEach { try $0.delete() }
        let file2 = try obtainWritableFile(orchestrator, writeSize: 1)

        XCTAssertNotEqual(file1.name, file2.name)
    }

    /// If two orchestrator instances run against the same directory each starts
    /// with no `_currentFile`, so each creates its own file on first use.
    func testWhenRequestedFirstTime_eachOrchestratorInstanceCreatesNewWritableFile() throws {
        let orchestrator1 = configureOrchestrator(using: RelativeDateProvider())
        let orchestrator2 = configureOrchestrator(
            using: RelativeDateProvider(startingFrom: Date().secondsAgo(0.01))
        )

        _ = try obtainWritableFile(orchestrator1, writeSize: 1)
        XCTAssertEqual(try temporaryDirectory.files().count, 1)

        _ = try obtainWritableFile(orchestrator2, writeSize: 1)
        XCTAssertEqual(try temporaryDirectory.files().count, 2)
    }

    func testWhenFilesDirectorySizeIsBig_itKeepsItUnderLimit_byRemovingOldestFilesFirst() throws {
        let oneMB: UInt64 = 1024 * 1024

        let orchestrator = FilesOrchestrator(
            directory: temporaryDirectory,
            performance: StoragePerformanceMock(
                maxFileSize: oneMB,
                maxDirectorySize: 3 * oneMB,
                maxFileAgeForWrite: .distantFuture,
                minFileAgeForRead: .mockAny(),
                maxFileAgeForRead: .distantFuture,
                maxObjectsInFile: 1,
                maxObjectSize: .max,
                synchronousWrite: true
            ),
            dateProvider: RelativeDateProvider(advancingBySeconds: 1)
        )

        let file1 = try obtainWritableFile(orchestrator, writeSize: oneMB)
        try file1.append(data: .mock(ofSize: oneMB), synchronized: false)

        let file2 = try obtainWritableFile(orchestrator, writeSize: oneMB)
        try file2.append(data: .mock(ofSize: oneMB), synchronized: true)

        let file3 = try obtainWritableFile(orchestrator, writeSize: oneMB + 1)
        try file3.append(data: .mock(ofSize: oneMB + 1), synchronized: false)

        XCTAssertEqual(try temporaryDirectory.files().count, 3)

        // Directory has reached its maximum size — the next request should purge the oldest.
        let file4 = try obtainWritableFile(orchestrator, writeSize: oneMB)
        XCTAssertEqual(try temporaryDirectory.files().count, 3)
        XCTAssertNil(try? temporaryDirectory.file(named: file1.name))
        try file4.append(data: .mock(ofSize: oneMB + 1), synchronized: true)

        _ = try obtainWritableFile(orchestrator, writeSize: oneMB)
        XCTAssertEqual(try temporaryDirectory.files().count, 3)
        XCTAssertNil(try? temporaryDirectory.file(named: file2.name))
    }

    // MARK: - Readable file tests

    func testGivenDefaultReadConditions_whenThereAreNoFiles_itReturnsNil() throws {
        let dateProvider = RelativeDateProvider()
        let orchestrator = configureOrchestrator(using: dateProvider)
        dateProvider.advance(bySeconds: 1 + performance.minFileAgeForRead)
        XCTAssertNil(try orchestrator.getReadableFile())
    }

    func testGivenDefaultReadConditions_whenFileIsOldEnough_itReturnsReadableFile() throws {
        let dateProvider = RelativeDateProvider()
        let orchestrator = configureOrchestrator(using: dateProvider)
        let file = try temporaryDirectory.createFile(named: dateProvider.currentDate().toFileName)

        dateProvider.advance(bySeconds: 1 + performance.minFileAgeForRead)
        XCTAssertEqual(try orchestrator.getReadableFile()?.name, file.name)
    }

    func testGivenDefaultReadConditions_whenFileIsTooYoung_itReturnsNoFile() throws {
        let dateProvider = RelativeDateProvider()
        let orchestrator = configureOrchestrator(using: dateProvider)
        _ = try temporaryDirectory.createFile(named: dateProvider.currentDate().toFileName)

        dateProvider.advance(bySeconds: 0.5 * performance.minFileAgeForRead)
        XCTAssertNil(try orchestrator.getReadableFile())
    }

    func testGivenDefaultReadConditions_whenThereAreSeveralFiles_itReturnsTheOldestOne() throws {
        let dateProvider = RelativeDateProvider(advancingBySeconds: 1)
        let orchestrator = configureOrchestrator(using: dateProvider)
        let fileNames = (0..<4).map { _ in dateProvider.currentDate().toFileName }
        try fileNames.forEach { fileName in _ = try temporaryDirectory.createFile(named: fileName) }

        dateProvider.advance(bySeconds: 1 + performance.minFileAgeForRead)
        XCTAssertEqual(try orchestrator.getReadableFile()?.name, fileNames[0])
        try temporaryDirectory.file(named: fileNames[0]).delete()
        XCTAssertEqual(try orchestrator.getReadableFile()?.name, fileNames[1])
        try temporaryDirectory.file(named: fileNames[1]).delete()
        XCTAssertEqual(try orchestrator.getReadableFile()?.name, fileNames[2])
        try temporaryDirectory.file(named: fileNames[2]).delete()
        XCTAssertEqual(try orchestrator.getReadableFile()?.name, fileNames[3])
        try temporaryDirectory.file(named: fileNames[3]).delete()
        XCTAssertNil(try orchestrator.getReadableFile())
    }

    func testGivenDefaultReadConditions_whenFileIsTooOld_itGetsDeleted() throws {
        let dateProvider = RelativeDateProvider()
        let orchestrator = configureOrchestrator(using: dateProvider)
        _ = try temporaryDirectory.createFile(named: dateProvider.currentDate().toFileName)

        dateProvider.advance(bySeconds: 2 * performance.maxFileAgeForRead)

        XCTAssertNil(try orchestrator.getReadableFile())
        XCTAssertEqual(try temporaryDirectory.files().count, 0)
    }

    func testItDeletesReadableFile() throws {
        let dateProvider = RelativeDateProvider()
        let orchestrator = configureOrchestrator(using: dateProvider)
        _ = try temporaryDirectory.createFile(named: dateProvider.currentDate().toFileName)

        dateProvider.advance(bySeconds: 1 + performance.minFileAgeForRead)

        let readableFile = try orchestrator.getReadableFile().unwrapOrThrow()
        XCTAssertEqual(try temporaryDirectory.files().count, 1)
        try orchestrator.delete(readableFile: readableFile)
        XCTAssertEqual(try temporaryDirectory.files().count, 0)
    }

    // MARK: - File names tests

    // swiftlint:disable number_separator
    func testItTurnsFileNameIntoFileCreationDate() {
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 0)), "0")
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456)), "123456000")
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456.7)), "123456700")
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456.78)), "123456780")
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456.789)), "123456789")

        // microseconds rounding
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456.1111)), "123456111")
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456.1115)), "123456112")
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456.1119)), "123456112")

        // overflows
        let maxDate = Date(timeIntervalSinceReferenceDate: TimeInterval.greatestFiniteMagnitude)
        let minDate = Date(timeIntervalSinceReferenceDate: -TimeInterval.greatestFiniteMagnitude)
        XCTAssertEqual(fileNameFrom(fileCreationDate: maxDate), "0")
        XCTAssertEqual(fileNameFrom(fileCreationDate: minDate), "0")
    }

    func testItTurnsFileCreationDateIntoFileName() {
        XCTAssertEqual(fileCreationDateFrom(fileName: "0"), Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertEqual(fileCreationDateFrom(fileName: "123456000"), Date(timeIntervalSinceReferenceDate: 123456))
        XCTAssertEqual(fileCreationDateFrom(fileName: "123456700"), Date(timeIntervalSinceReferenceDate: 123456.7))
        XCTAssertEqual(fileCreationDateFrom(fileName: "123456780"), Date(timeIntervalSinceReferenceDate: 123456.78))
        XCTAssertEqual(fileCreationDateFrom(fileName: "123456789"), Date(timeIntervalSinceReferenceDate: 123456.789))

        // ignores invalid names
        let invalidFileName = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        XCTAssertEqual(fileCreationDateFrom(fileName: invalidFileName), Date(timeIntervalSinceReferenceDate: 0))
    }

    // swiftlint:enable number_separator
}
