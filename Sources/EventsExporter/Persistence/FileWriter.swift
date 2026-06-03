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
    /// Optional telemetry observer notified about serialization / payload size.
    private let observer: PayloadObserver?
    /// Events written to / time spent serializing the currently-open file. Only
    /// touched on `queue`. Reported as `payloadFinalized` when the file rolls
    /// over or is explicitly closed.
    private var pendingEventCount: Int = 0
    private var pendingSerializationMs: Double = 0
    /// Queue used to synchronize files access (read / write).
    internal let queue: DispatchQueue

    init(entity: String,
         dataFormat: DataFormatType,
         orchestrator: FilesOrchestratorType,
         encoder: JSONEncoder,
         observer: PayloadObserver? = nil)
    {
        self.dataFormat = dataFormat
        self.orchestrator = orchestrator
        self.encoder = encoder
        self.observer = observer
        self.queue = DispatchQueue(label: "datadogtest.filewriter.\(entity)",
                                   target: .global(qos: .userInteractive))
    }

    /// Replaces the current data format and closes the writable file so the
    /// next write starts a new file with the new header.
    func update(dataFormat: DataFormatType) {
        queue.sync(flags: .barrier) {
            finalizeCurrentPayload()
            orchestrator.closeWritableFile()
            self.dataFormat = dataFormat
        }
    }

    /// Closes the current writable file. The next write will open a new file.
    /// Required before `FileReader.getAllReadableFiles()` so the in-progress
    /// file isn't returned mid-write.
    func closeCurrentFile() {
        queue.sync(flags: .barrier) {
            finalizeCurrentPayload()
            orchestrator.closeWritableFile()
        }
    }

    /// Reports the event count and summed serialization time of the file that is
    /// being closed, if any. Must be called on `queue`.
    private func finalizeCurrentPayload() {
        guard pendingEventCount > 0 else { return }
        observer?.payloadFinalized(eventCount: pendingEventCount, serializationMs: pendingSerializationMs)
        pendingEventCount = 0
        pendingSerializationMs = 0
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
        observer?.eventEnqueued()
        let encodeStart = observer.map { _ in DispatchTime.now() }
        let data = try encoder.encode(value)
        let eventMs = encodeStart.map {
            Double(DispatchTime.now().uptimeNanoseconds - $0.uptimeNanoseconds) / 1_000_000
        }
        // `withWritableFile` claims the file for the duration of `body`, so
        // the upload worker's reader cannot list-and-delete the file mid-
        // write. Once the closure returns, the file becomes visible to the
        // reader.
        try orchestrator.withWritableFile(writeSize: UInt64(data.count)) { writable, isNew in
            // A new file means the previous one is finalized; report its totals
            // and start accumulating for the new payload. This event's
            // serialization time belongs to the new payload.
            if isNew {
                finalizeCurrentPayload()
            }
            pendingEventCount += 1
            if let eventMs { pendingSerializationMs += eventMs }
            let payload = try isNew ? (dataFormat.prefix + data) : (dataFormat.separator + data)
            try writable.append(data: payload, synchronized: sync)
        }
    }
}
