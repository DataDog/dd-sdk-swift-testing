/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

/// Abstracts the `DataUploadWorker`, so we can have no-op uploader in tests.
internal protocol DataUploadWorkerType {
    /// update file format. Only header can be updated or cached files will be broken
    func update(dataFormat: DataFormatType)
    
    /// synchronously upload all stored data
    func flush() throws -> Bool
    
    /// Cancels scheduled uploads and stops scheduling next ones.
    /// - It does not affect the upload that has already begun.
    /// - It blocks the caller thread if called in the middle of upload execution.
    func stop()
}

internal class DataUploadWorker: DataUploadWorkerType {
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
            guard let self = self else {
                return
            }
            
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
        guard let work = uploadWork else {
            return
        }
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
    
    func update(dataFormat: DataFormatType) {
        queue.sync { fileReader.update(dataFormat: dataFormat) }
    }

    /// This method  gets remaining files at once, and uploads them
    /// It assures that periodic uploader cannot read or upload the files while the flush is being processed
    internal func flush() throws -> Bool {
        var result: Bool = false
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

    /// Cancels scheduled uploads and stops scheduling next ones.
    /// - It does not affect the upload that has already begun.
    /// - It blocks the caller thread if called in the middle of upload execution.
    internal func stop() {
        queue.sync {
            // This cancellation must be performed on the `queue` to ensure that it is not called
            // in the middle of a `DispatchWorkItem` execution - otherwise, as the pending block would be
            // fully executed, it will schedule another upload by calling `nextScheduledWork(after:)` at the end.
            self.uploadWork?.cancel()
            self.uploadWork = nil
        }
    }
    
    private func upload(data: Data) -> UploadResult {
        let uploadStatus = self.dataUploader.upload(data: data).await().get()
        // Delete or keep batch depending on the upload status
        if uploadStatus.needsRetry {
            if let waitTime = uploadStatus.waitTime {
                if delay.set(delay: waitTime) { // we can wait this time
                    return .retry
                } else {
                    return .failed
                }
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
            switch self {
            case .retry:
                return true
            default:
                return false
            }
        }
    }
}
