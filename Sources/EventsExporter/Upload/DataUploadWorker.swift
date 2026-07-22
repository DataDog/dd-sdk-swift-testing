/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// Abstracts the `DataUploadWorker` so we can swap it for a no-op in tests.
internal protocol DataUploadWorkerType: Sendable {
    /// Replace the data format. Only the header (prefix) can be changed —
    /// already-flushed files keep their original format until they upload.
    func update(dataFormat: DataFormatType)

    /// Synchronously drain all stored data (with retry on transient failures).
    /// Returns `false` if a non-retriable failure was encountered.
    ///
    /// `timeout` is a total wall-clock budget for the whole drain (e.g. an
    /// OpenTelemetry `forceFlush` timeout). When it elapses, remaining batches
    /// are left on disk for a later run. `nil` means "no total budget" — each
    /// attempt is still bounded by the default per-attempt cap.
    func flush(timeout: TimeInterval?) throws -> Bool

    /// Cancel scheduled uploads and stop scheduling new ones. Does not
    /// interrupt an upload that has already started; will block the caller
    /// if invoked mid-upload.
    func stop()
}

internal final class DataUploadWorker: DataUploadWorkerType, @unchecked Sendable {
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
    /// Request timeout for upload
    private let uploadTimeout: TimeInterval
    /// Upload work scheduled by this worker.
    private var uploadWork: DispatchWorkItem?
    /// Optional telemetry observer notified about upload attempts / drops.
    private let observer: UploadObserver?
    /// Logger for upload status and errors.
    private let log: Logger

    init(
        fileReader: FileReader,
        dataUploader: DataUploaderType,
        delay: Delay,
        uploadTimeout: TimeInterval,
        featureName: String,
        priority: DispatchQoS,
        log: Logger,
        observer: UploadObserver? = nil
    ) {
        self.fileReader = fileReader
        self.dataUploader = dataUploader
        self.delay = delay
        self.uploadTimeout = uploadTimeout
        self.observer = observer
        self.log = log
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
                if self.upload(data: batch.data, timeout: uploadTimeout) == .success {
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
    ///
    /// `timeout`, when set, is a total wall-clock budget for the whole drain:
    /// once it elapses no further attempt is started and remaining batches are
    /// left on disk for a later run. Each individual attempt is additionally
    /// bounded by the smaller of the remaining budget and the default
    /// per-attempt cap.
    func flush(timeout: TimeInterval?) throws -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout ?? uploadTimeout)
        var result = true
        try queue.sync {
            var iterator = try fileReader.getRemainingBatches()
            batchLoop: while let batchRes = iterator.next() {
                guard case .success(let batch) = batchRes else {
                    result = false
                    break
                }
                var status: UploadResult
                repeat {
                    let attemptTimeout = max(0, deadline.timeIntervalSinceNow)
                    guard attemptTimeout > 0 else {
                        // Total flush budget exhausted; leave remaining batches
                        // on disk rather than blocking teardown further.
                        log.print("[\(featureName)] flush timed out; leaving remaining batches on disk")
                        result = false
                        break batchLoop
                    }
                    status = upload(data: batch.data, timeout: attemptTimeout)
                    switch status {
                    case .success:
                        try self.fileReader.markBatchAsRead(batch)
                        result = true
                    case .failed:
                        result = false
                    case .retry:
                        // Don't sleep past the deadline.
                        Thread.sleep(forTimeInterval: min(delay.current, max(0, deadline.timeIntervalSinceNow)))
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

    private func upload(data: Data, timeout: TimeInterval?) -> UploadResult {
        let start = observer != nil ? DispatchTime.now() : nil
        let uploadStatus = self.dataUploader.upload(data: data, timeout: timeout)
        let result: UploadResult
        if uploadStatus.needsRetry {
            if let waitTime = uploadStatus.waitTime {
                result = delay.set(delay: waitTime) ? .retry : .failed
            } else {
                delay.increase()
                result = .retry
            }
        } else {
            delay.decrease()
            result = .success
        }
        switch result {
        case .success:
            log.debug("[\(featureName)] batch uploaded (\(data.count) bytes)")
        case .retry:
            let reason = uploadStatus.failureDescription.map { ": \($0)" } ?? ""
            log.print("[\(featureName)] upload failed, will retry\(reason)")
        case .failed:
            let reason = uploadStatus.failureDescription.map { ": \($0)" } ?? ""
            log.print("[\(featureName)] upload failed, dropping batch\(reason)")
        }
        if let observer, let start {
            let durationMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            observer.uploadAttempt(payloadBytes: data.count, durationMs: durationMs,
                                   success: result == .success, retriable: result == .retry)
        }
        return result
    }

    private enum UploadResult: Equatable {
        case success
        case retry
        case failed

        var isRetry: Bool {
            if case .retry = self { return true }
            return false
        }
    }
}
