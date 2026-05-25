/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal final class FileWriter {
    /// Data writing format.
    private var dataFormat: DataFormatType
    /// Orchestrator producing reference to writable file.
    private let orchestrator: FilesOrchestratorType
    /// JSON encoder used to encode data.
    private let encoder: JSONEncoder
    /// Queue used to synchronize files access (read / write).
    internal let queue: DispatchQueue

    init(entity: String,
         dataFormat: DataFormatType,
         orchestrator: FilesOrchestratorType,
         encoder: JSONEncoder)
    {
        self.dataFormat = dataFormat
        self.orchestrator = orchestrator
        self.encoder = encoder
        self.queue = DispatchQueue(label: "datadogtest.filewriter.\(entity)",
                                   target: .global(qos: .userInteractive))
    }

    /// Replaces the current data format and closes the writable file so the
    /// next write starts a new file with the new header.
    func update(dataFormat: DataFormatType) {
        queue.sync(flags: .barrier) {
            orchestrator.closeWritableFile()
            self.dataFormat = dataFormat
        }
    }

    /// Closes the current writable file. The next write will open a new file.
    /// Required before `FileReader.getAllReadableFiles()` so the in-progress
    /// file isn't returned mid-write.
    func closeCurrentFile() {
        queue.sync(flags: .barrier) { orchestrator.closeWritableFile() }
    }

    // MARK: - Writing data

    /// Encodes and writes `value` asynchronously. Errors are logged and swallowed.
    func write<T: Encodable>(value: T) {
        queue.async { [weak self] in
            do {
                try self?.write(value: value, sync: false)
            } catch {
                Log.print("🔥 Failed to write file: \(error)")
            }
        }
    }

    /// Encodes and writes `value` synchronously, surfacing errors to the caller.
    func writeSync<T: Encodable>(value: T) throws {
        try queue.sync { try write(value: value, sync: true) }
    }

    private func write<T: Encodable>(value: T, sync: Bool) throws {
        let data = try encoder.encode(value)
        do {
            try appendOnce(data: data, sync: sync)
        } catch {
            // The upload worker reads-and-deletes files on its own queue. If
            // it picks up the writable file between `getWritableFile` and the
            // `append` call, the append throws ENOENT because the file
            // vanished. Drop the now-dangling `_currentFile` reference and
            // retry once with a freshly allocated file so the value isn't
            // lost. Other IO errors (permission denied, disk full, etc.)
            // propagate as before.
            guard Self.isMissingFileError(error) else { throw error }
            orchestrator.closeWritableFile()
            try appendOnce(data: data, sync: sync)
        }
    }

    private func appendOnce(data: Data, sync: Bool) throws {
        let writable = try orchestrator.getWritableFile(writeSize: UInt64(data.count))
        let payload = writable.isNew ? (dataFormat.prefix + data) : (dataFormat.separator + data)
        try writable.file.append(data: payload, synchronized: sync)
    }

    /// `true` if `error` indicates the target file was missing — Cocoa surfaces
    /// this as `NSFileNoSuchFileError` / `NSFileReadNoSuchFileError`, POSIX as
    /// `ENOENT`. Used to distinguish a deleted-out-from-under-us file from
    /// real IO failures.
    private static func isMissingFileError(_ error: Error) -> Bool {
        let ns = error as NSError
        switch ns.domain {
        case NSCocoaErrorDomain:
            return ns.code == NSFileNoSuchFileError || ns.code == NSFileReadNoSuchFileError
        case NSPOSIXErrorDomain:
            return ns.code == Int(ENOENT)
        default:
            return false
        }
    }
}
