/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// Abstracts the `DataUploadWorker` so we can swap it for a no-op in tests.
internal protocol DataUploadWorkerType {
    /// Replace the data format. Only the header (prefix) can be changed —
    /// already-flushed files keep their original format until they upload.
    func update(dataFormat: DataFormatType)

    /// Synchronously drain all stored data (with retry on transient failures).
    /// Returns `false` if a non-retriable failure was encountered.
    func flush() throws -> Bool

    /// Cancel scheduled uploads and stop scheduling new ones. Does not
    /// interrupt an upload that has already started; will block the caller
    /// if invoked mid-upload.
    func stop()
}

internal final class DataUploadWorker: DataUploadWorkerType {
    /// Queue to execute uploads.
    internal let queue: DispatchQueue
    /// File reader providing data to upload.
    private let fileReader: FileReader
    /// Data uploader sending data to server.
    private let dataUploader: DataUploaderType
    /// Name of the feature this worker is performing uploads for.
    private let featureName: String
    /// Delay used to schedule consecutive uploads.
    private var delay: Delay
    /// Upload work scheduled by this worker.
    private var uploadWork: DispatchWorkItem?

    init(
        fileReader: FileReader,
        dataUploader: DataUploaderType,
        delay: Delay,
        featureName: String,
        priority: DispatchQoS
    ) {
        self.fileReader = fileReader
        self.dataUploader = dataUploader
        self.delay = delay
        self.queue = DispatchQueue(label: "datadogtest.datauploadworker.\(featureName)",
                                   target: .global(qos: priority.qosClass))
        self.featureName = featureName

        let uploadWork = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            let batch: Batch?
            do {
                batch = try self.fileReader.getNextBatch()
            } catch {
                batch = nil // file is broken
            }

            if let batch = batch {
                if self.upload(data: batch.data) == .success {
                    try? self.fileReader.markBatchAsRead(batch)
                }
            } else {
                self.delay.increase()
            }

            self.scheduleNextUpload(after: self.delay.current)
        }
        self.uploadWork = uploadWork
        scheduleNextUpload(after: self.delay.current)
    }

    private func scheduleNextUpload(after delay: TimeInterval) {
        guard let work = uploadWork else { return }
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func update(dataFormat: DataFormatType) {
        queue.sync { fileReader.update(dataFormat: dataFormat) }
    }

    /// Drains all pending batches synchronously. Holds the upload queue for
    /// the duration so the periodic worker can't interleave reads with the flush.
    func flush() throws -> Bool {
        var result = true
        try queue.sync {
            var iterator = try fileReader.getRemainingBatches()
            while let batchRes = iterator.next() {
                guard case .success(let batch) = batchRes else {
                    result = false
                    break
                }
                var status: UploadResult
                repeat {
                    status = upload(data: batch.data)
                    switch status {
                    case .success:
                        try self.fileReader.markBatchAsRead(batch)
                        result = true
                    case .failed:
                        result = false
                    case .retry:
                        Thread.sleep(forTimeInterval: delay.current)
                    }
                } while status.isRetry
                guard result else { break }
            }
        }
        return result
    }

    func stop() {
        queue.sync {
            // Cancellation must happen on `queue` — otherwise a pending block could
            // execute fully and schedule another upload at the end.
            self.uploadWork?.cancel()
            self.uploadWork = nil
        }
    }

    private func upload(data: Data) -> UploadResult {
        let uploadStatus = self.dataUploader.upload(data: data)
        if uploadStatus.needsRetry {
            if let waitTime = uploadStatus.waitTime {
                return delay.set(delay: waitTime) ? .retry : .failed
            } else {
                delay.increase()
                return .retry
            }
        } else {
            delay.decrease()
            return .success
        }
    }

    private enum UploadResult {
        case success
        case retry
        case failed

        var isRetry: Bool {
            if case .retry = self { return true }
            return false
        }
    }
}
