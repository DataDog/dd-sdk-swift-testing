/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// File orchestration logic. Thread-safe: a single orchestrator is shared
/// between the writer queue and the upload-worker queue, and its
/// `withWritableFile(...)` scope is the synchronisation point — while the
/// writer holds the scope, the chosen file is excluded from the reader's
/// view so a partially-written file can never be picked up and deleted out
/// from under the writer.
internal protocol FilesOrchestratorType {
    // Read
    func getReadableFile() throws -> ReadableFile?
    func delete(readableFile: ReadableFile) throws
    func getAllReadableFiles() throws -> [ReadableFile]

    // Write — closure-scoped: the file is "claimed" for the duration of
    // `body`, and the reader will skip it until the body returns.
    @discardableResult
    func withWritableFile<T>(
        writeSize: UInt64,
        _ body: (_ file: WritableFile, _ isNew: Bool) throws -> T
    ) throws -> T

    /// Drop the cached "current writable" reference so the next
    /// `withWritableFile(...)` allocates a fresh file. Used when the writer
    /// finishes a logical batch (e.g. before flush) or when the data format
    /// changes and the header needs to be rewritten.
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

    /// All mutable orchestrator state lives in this struct. Its `mutating` /
    /// non-mutating methods are the *only* way to read or change the state,
    /// and they're reachable exclusively through `Synced.use(_:)` /
    /// `Synced.update(_:)` — so by construction, every state access is
    /// performed under the lock.
    private struct State {
        var currentFile: FileInfo? = nil
        var currentFileUseCount: Int = 0
        /// File names the writer is currently appending to. The reader
        /// excludes these from its view; entries are removed when the
        /// `withWritableFile(...)` scope ends. Names (not URLs) are used as
        /// the key because `directory.createFile(...)` and
        /// `FileManager.contentsOfDirectory(at:)` can return URLs whose
        /// paths differ in canonicalisation (`/var` vs `/private/var`),
        /// which makes URL equality unreliable — but the file name is the
        /// final path component, unique within the directory, and stable.
        var activeWrites: Set<String> = []

        // MARK: - Writer

        /// Pick (or create) a file for the next write and mark it claimed.
        /// Returns the concrete `File` so the caller can record the URL for
        /// the release step in `releaseWritable(url:)`.
        mutating func acquireWritable(writeSize: UInt64,
                                      directory: borrowing Directory,
                                      performance: borrowing StoragePerformancePreset,
                                      dateProvider: borrowing DateProvider) throws -> (file: File, isNew: Bool) {
            if writeSize > performance.maxObjectSize {
                throw ExporterError(description: "data exceeds the maximum size of \(performance.maxObjectSize) bytes.")
            }
            let info = try chooseWritableFile(writeSize: writeSize, directory: directory,
                                              performance: performance, dateProvider: dateProvider)
            activeWrites.insert(info.file.name)
            return (file: info.file, isNew: try info.isNew)
        }

        mutating func releaseWritable(name: String) {
            activeWrites.remove(name)
        }

        mutating func closeCurrentFile() {
            currentFile = nil
            currentFileUseCount = 0
        }

        private mutating func chooseWritableFile(writeSize: UInt64,
                                                 directory: borrowing Directory,
                                                 performance: borrowing StoragePerformancePreset,
                                                 dateProvider: borrowing DateProvider) throws -> FileInfo
        {
            if let reusable = try reuseWritableFileIfPossible(writeSize: writeSize,
                                                              performance: performance,
                                                              dateProvider: dateProvider)
            {
                currentFileUseCount += 1
                return reusable
            }
            // `fileNameFrom` is millisecond-resolution. Two writes that land
            // in the same millisecond — likely when `maxFileAgeForWrite == 0`
            // forces every write to roll over — would collide on the file
            // name, and `FileManager.createFile(atPath:contents:attributes:)`
            // silently overwrites an existing file. Bump the timestamp until
            // we land on an unused name so the previous file's content
            // isn't lost.
            var creationDate = dateProvider.currentDate()
            while directory.hasFile(named: fileNameFrom(fileCreationDate: creationDate)) {
                creationDate = creationDate.addingTimeInterval(0.001)
            }
            let file = try directory.createFile(named: fileNameFrom(fileCreationDate: creationDate))
            let newFile = FileInfo(file: file, creationDate: creationDate)
            currentFile = newFile
            currentFileUseCount = 1
            return newFile
        }

        private func reuseWritableFileIfPossible(writeSize: UInt64,
                                                 performance: borrowing StoragePerformancePreset,
                                                 dateProvider: borrowing DateProvider) throws -> FileInfo?
        {
            guard let currentFile = currentFile else { return nil }
            // If the file was deleted off-disk between writes, fall back to creating a new one.
            guard let currentSize = try? currentFile.file.size() else { return nil }
            let fileCanBeUsedMoreTimes = (currentFileUseCount + 1) <= performance.maxObjectsInFile
            let currentFileAge = dateProvider.currentDate().timeIntervalSince(currentFile.creationDate)
            let fileIsRecentEnough = currentFileAge <= performance.maxFileAgeForWrite
            let fileHasRoomForMore = (currentSize + writeSize) <= performance.maxFileSize

            if fileIsRecentEnough, fileHasRoomForMore, fileCanBeUsedMoreTimes {
                return currentFile
            }
            return nil
        }

        // MARK: - Reader

        /// Reader results paired with the byte sizes of any files dropped
        /// (deleted for exceeding `maxFileAgeForRead`) during the scan. The
        /// caller reports the drops *outside* the state lock.
        func oldestReadableFile(directory: borrowing Directory,
                                performance: borrowing StoragePerformancePreset,
                                dateProvider: borrowing DateProvider) throws -> (file: ReadableFile?, droppedBytes: [Int])
        {
            let (infos, droppedBytes) = try fileInfos(directory: directory,
                                                      performance: performance,
                                                      dateProvider: dateProvider)
            guard let oldest = infos.first else { return (nil, droppedBytes) }
            let age = dateProvider.currentDate().timeIntervalSince(oldest.creationDate)
            return (age >= performance.minFileAgeForRead ? oldest.file : nil, droppedBytes)
        }

        func allReadableFiles(directory: borrowing Directory,
                              performance: borrowing StoragePerformancePreset,
                              dateProvider: borrowing DateProvider) throws -> (files: [ReadableFile], droppedBytes: [Int])
        {
            let (infos, droppedBytes) = try fileInfos(directory: directory,
                                                      performance: performance,
                                                      dateProvider: dateProvider)
            return (infos.map { $0.file }, droppedBytes)
        }

        private func fileInfos(directory: borrowing Directory,
                               performance: borrowing StoragePerformancePreset,
                               dateProvider: borrowing DateProvider) throws -> (files: [FileInfo], droppedBytes: [Int])
        {
            let allFiles = try directory.files()
                .filter { !activeWrites.contains($0.name) }
                .map { FileInfo(file: $0) }

            var readableFiles: [FileInfo] = []
            readableFiles.reserveCapacity(allFiles.count)
            var droppedBytes: [Int] = []
            for info in allFiles {
                let fileAge = dateProvider.currentDate().timeIntervalSince(info.creationDate)
                if fileAge > performance.maxFileAgeForRead {
                    // Too old to ever upload — count it as a dropped payload.
                    let size = (try? info.file.size()).map(Int.init) ?? 0
                    try info.file.delete()
                    droppedBytes.append(size)
                } else {
                    readableFiles.append(info)
                }
            }

            return (readableFiles.sorted(), droppedBytes)
        }
    }

    /// All state mutation goes through `Synced` — there's no other way to
    /// reach `State`'s methods, so we can't accidentally touch the state
    /// outside the lock.
    private let state: Synced<State>
    
    private let directory: Directory
    private let dateProvider: DateProvider
    private let performance: StoragePerformancePreset
    /// Invoked (outside the state lock) with the byte size of each file removed
    /// without being uploaded — too old (`maxFileAgeForRead`) or purged to keep
    /// the directory under `maxDirectorySize`. Wired to `endpoint_payload.dropped`.
    private let onDrop: (@Sendable (Int) -> Void)?

    init(directory: Directory,
         performance: StoragePerformancePreset,
         dateProvider: DateProvider,
         onDrop: (@Sendable (Int) -> Void)? = nil)
    {
        self.directory = directory
        self.dateProvider = dateProvider
        self.performance = performance
        self.onDrop = onDrop
        self.state = Synced(.init())
    }

    // MARK: - `WritableFile` orchestration

    func withWritableFile<T>(
        writeSize: UInt64,
        _ body: (_ file: WritableFile, _ isNew: Bool) throws -> T
    ) throws -> T {
        // Pick (and claim) the file under the lock; release the lock before
        // running `body` so the slow file I/O doesn't block the reader.
        let chosen: (file: File, isNew: Bool, active: Set<String>) = try state.update { state in
            let acquired = try state.acquireWritable(writeSize: writeSize,
                                                     directory: directory,
                                                     performance: performance,
                                                     dateProvider: dateProvider)
            return (file: acquired.file, isNew: acquired.isNew, active: state.activeWrites)
        }
        defer { state.update { $0.releaseWritable(name: chosen.file.name) } }

        // NOTE: RUMM-610 As purging files directory is a memory-expensive operation, do it only when we know
        // that a new file will be created. With SDK's `PerformancePreset` this gives
        // the process enough time to not over-allocate internal `_FileCache` and `_NSFastEnumerationEnumerator`
        // objects, resulting with a flat allocations graph in a long term.
        if chosen.isNew {
            try purgeFilesDirectoryIfNeeded(activeWrites: chosen.active)
        }
        return try body(chosen.file, chosen.isNew)
    }

    func closeWritableFile() {
        state.update { $0.closeCurrentFile() }
    }

    // MARK: - `ReadableFile` orchestration

    func getReadableFile() throws -> ReadableFile? {
        let (file, droppedBytes) = try state.use {
            try $0.oldestReadableFile(directory: directory,
                                      performance: performance,
                                      dateProvider: dateProvider)
        }
        reportDrops(droppedBytes)
        return file
    }

    func getAllReadableFiles() throws -> [ReadableFile] {
        let (files, droppedBytes) = try state.use {
            try $0.allReadableFiles(directory: directory,
                                    performance: performance,
                                    dateProvider: dateProvider)
        }
        reportDrops(droppedBytes)
        return files
    }

    /// Report dropped-payload sizes. Called outside the state lock so the
    /// observer (which may touch its own locks) can't contend with file ops.
    private func reportDrops(_ droppedBytes: [Int]) {
        guard let onDrop else { return }
        droppedBytes.forEach(onDrop)
    }

    func delete(readableFile: ReadableFile) throws {
        // No state to mutate, but we still hold the lock so the delete can't
        // race with a concurrent reuse-check (`file.size()`) or with another
        // delete picking the same file.
        try state.use { _ in try readableFile.delete() }
    }
    
    /// Removes oldest files from the directory if it becomes too big.
    /// Files currently being written to are never purged.
    private func purgeFilesDirectoryIfNeeded(activeWrites: borrowing Set<String>) throws {
        let files = try directory.files()
            .filter { !activeWrites.contains($0.name) }
            .map { FileInfo(file: $0) }
            .compactMap { (info) -> FileInfo? in
                let fileAge = dateProvider.currentDate().timeIntervalSince(info.creationDate)
                if fileAge > performance.maxFileAgeForRead {
                    // Too old to ever upload — count it as a dropped payload.
                    let size = (try? info.file.size()).map(Int.init) ?? 0
                    try info.file.delete()
                    onDrop?(size)
                    return nil
                }
                return info
            }.sorted()
        var filesWithSize = try files.map { (file: $0.file, size: try $0.file.size()) }
        let accumulated = filesWithSize.map { $0.size }.reduce(0, +)
        if accumulated > performance.maxDirectorySize {
            let sizeToFree = accumulated - performance.maxDirectorySize
            var sizeFreed: UInt64 = 0
            while sizeFreed < sizeToFree, !filesWithSize.isEmpty {
                let fileWithSize = filesWithSize.removeFirst()
                try fileWithSize.file.delete()
                sizeFreed += fileWithSize.size
                // Purged to stay under the directory size limit — also a drop.
                onDrop?(Int(fileWithSize.size))
            }
        }
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
