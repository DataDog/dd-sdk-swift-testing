/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// File orchestration logic.
/// Type is not thread-safe and should be synchronised by reader and writer.
internal protocol FilesOrchestratorType {
    // Read
    func getReadableFile() throws -> ReadableFile?
    func delete(readableFile: ReadableFile) throws

    /// Caller must close the writable file (and drain the writer queue) before
    /// calling this method, or the in-progress writable file will be returned
    /// to the uploader mid-write.
    func getAllReadableFiles() throws -> [ReadableFile]

    // Write
    func getWritableFile(writeSize: UInt64) throws -> (file: WritableFile, isNew: Bool)
    func closeWritableFile()
}

internal final class FilesOrchestrator: FilesOrchestratorType {
    struct FileInfo: Comparable {
        let file: File
        let creationDate: Date
        var isNew: Bool { get throws { try file.size() == 0 } }

        init(file: File, creationDate: Date? = nil) {
            self.file = file
            self.creationDate = creationDate ?? fileCreationDateFrom(fileName: file.name)
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.creationDate < rhs.creationDate
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.file == rhs.file && lhs.creationDate == rhs.creationDate
        }
    }

    /// Directory where files are stored.
    private let directory: Directory
    /// Date provider.
    private let dateProvider: DateProvider
    /// Performance rules for writing and reading files.
    private let performance: StoragePerformancePreset
    /// Current writable file.
    private var _currentFile: FileInfo?
    private var _currentFileUseCount: Int = 0

    init(directory: Directory,
         performance: StoragePerformancePreset,
         dateProvider: DateProvider)
    {
        self.directory = directory
        self.performance = performance
        self.dateProvider = dateProvider
    }

    // MARK: - `WritableFile` orchestration

    func getWritableFile(writeSize: UInt64) throws -> (file: WritableFile, isNew: Bool) {
        if writeSize > performance.maxObjectSize {
            throw ExporterError(description: "data exceeds the maximum size of \(performance.maxObjectSize) bytes.")
        }

        if let reusable = try reuseWritableFileIfPossible(writeSize: writeSize) {
            _currentFileUseCount += 1
            return try (reusable.file, reusable.isNew)
        }

        // NOTE: RUMM-610 As purging files directory is a memory-expensive operation, do it only when we know
        // that a new file will be created. With SDK's `PerformancePreset` this gives
        // the process enough time to not over-allocate internal `_FileCache` and `_NSFastEnumerationEnumerator`
        // objects, resulting with a flat allocations graph in a long term.
        try purgeFilesDirectoryIfNeeded()

        let creationDate = dateProvider.currentDate()
        let file = try directory.createFile(named: fileNameFrom(fileCreationDate: creationDate))
        let newFile = FileInfo(file: file, creationDate: creationDate)
        _currentFile = newFile
        _currentFileUseCount = 1
        return try (newFile.file, newFile.isNew)
    }

    private func reuseWritableFileIfPossible(writeSize: UInt64) throws -> FileInfo? {
        guard let currentFile = _currentFile else { return nil }
        // If the file was deleted off-disk between writes, fall back to creating a new one.
        guard let currentSize = try? currentFile.file.size() else { return nil }
        let fileCanBeUsedMoreTimes = (_currentFileUseCount + 1) <= performance.maxObjectsInFile
        let currentFileAge = dateProvider.currentDate().timeIntervalSince(currentFile.creationDate)
        let fileIsRecentEnough = currentFileAge <= performance.maxFileAgeForWrite
        let fileHasRoomForMore = (currentSize + writeSize) <= performance.maxFileSize

        if fileIsRecentEnough, fileHasRoomForMore, fileCanBeUsedMoreTimes {
            return currentFile
        }
        return nil
    }

    func closeWritableFile() {
        _currentFile = nil
        _currentFileUseCount = 0
    }

    // MARK: - `ReadableFile` orchestration

    func getReadableFile() throws -> ReadableFile? {
        guard let oldestFile = try fileInfos().first else {
            return nil
        }
        let oldestFileAge = dateProvider.currentDate().timeIntervalSince(oldestFile.creationDate)
        return oldestFileAge >= performance.minFileAgeForRead ? oldestFile.file : nil
    }

    func getAllReadableFiles() throws -> [ReadableFile] {
        try fileInfos().map { $0.file }
    }

    func delete(readableFile: ReadableFile) throws {
        try readableFile.delete()
    }

    // MARK: - Directory size management

    /// Removes oldest files from the directory if it becomes too big.
    private func purgeFilesDirectoryIfNeeded() throws {
        var filesWithSize = try fileInfos()
            .map { (file: $0.file, size: try $0.file.size()) }
        let accumulated = filesWithSize.map { $0.size }.reduce(0, +)
        if accumulated > performance.maxDirectorySize {
            let sizeToFree = accumulated - performance.maxDirectorySize
            var sizeFreed: UInt64 = 0
            while sizeFreed < sizeToFree, !filesWithSize.isEmpty {
                let fileWithSize = filesWithSize.removeFirst()
                try fileWithSize.file.delete()
                sizeFreed += fileWithSize.size
            }
        }
    }

    private func deleteFileIfItsObsolete(info: FileInfo) throws -> FileInfo? {
        let fileAge = dateProvider.currentDate().timeIntervalSince(info.creationDate)
        if fileAge > performance.maxFileAgeForRead {
            try info.file.delete()
            return nil
        }
        return info
    }

    private func fileInfos() throws -> [FileInfo] {
        try directory.files()
            .map { FileInfo(file: $0) }
            .compactMap { try deleteFileIfItsObsolete(info: $0) }
            .sorted()
    }
}

/// File creation date is used as file name - timestamp in milliseconds is used for date representation.
/// This function converts file creation date into file name.
internal func fileNameFrom(fileCreationDate: Date) -> String {
    let milliseconds = fileCreationDate.timeIntervalSinceReferenceDate * 1_000
    let converted = (try? UInt64(withReportingOverflow: milliseconds)) ?? 0
    return String(converted)
}

/// File creation date is used as file name - timestamp in milliseconds is used for date representation.
/// This function converts file name into file creation date.
internal func fileCreationDateFrom(fileName: String) -> Date {
    let millisecondsSinceReferenceDate = TimeInterval(UInt64(fileName) ?? 0) / 1_000
    return Date(timeIntervalSinceReferenceDate: TimeInterval(millisecondsSinceReferenceDate))
}

private enum FixedWidthIntegerError<T: BinaryFloatingPoint>: Error {
    case overflow(overflowingValue: T)
}

private extension FixedWidthInteger {
    /* NOTE: RUMM-182
     Self(:) is commonly used for conversion, however it fatalError() in case of conversion failure
     Self(exactly:) does the exact same thing internally yet it returns nil instead of fatalError()
     It is not trivial to guess if the conversion would fail or succeed, therefore we use Self(exactly:)
     so that we don't need to guess in order to save the app from crashing

     IMPORTANT: If you pass floatingPoint to Self(exactly:) without rounded(), it may return nil
     */
    init<T: BinaryFloatingPoint>(withReportingOverflow floatingPoint: T) throws {
        guard let converted = Self(exactly: floatingPoint.rounded()) else {
            throw FixedWidthIntegerError<T>.overflow(overflowingValue: floatingPoint)
        }
        self = converted
    }
}
