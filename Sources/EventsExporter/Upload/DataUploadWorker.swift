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
    ///
    /// This overload blocks the calling thread and never suspends, so it stays
    /// usable on the teardown path (see `ClosureDataUploader`).
    func flush(timeout: TimeInterval?) throws -> Bool

    /// Drain all stored data, suspending rather than blocking. Same budget
    /// semantics as the synchronous overload.
    func flush(timeout: TimeInterval?) async throws -> Bool

    /// Cancel scheduled uploads and stop scheduling new ones. Does not wait for
    /// an upload that has already started — waiting would mean depending on the
    /// cooperative executor, which isn't guaranteed to run at process exit.
    func stop()

    /// Cancel scheduled uploads and await the in-flight upload cycle.
    func stop() async
}

internal final class DataUploadWorker: DataUploadWorkerType, @unchecked Sendable {
    /// All mutable worker state, guarded by `Synced`'s lock. The lock is only
    /// ever held for bookkeeping — never across an upload — so the synchronous
    /// teardown path can take it without waiting on the cooperative executor.
    private struct State {
        var delay: Delay
        var isStopped: Bool = false
        /// Names of files whose batch is currently being uploaded. Both the
        /// periodic loop and a concurrent flush skip these, so the same batch is
        /// never uploaded twice when they overlap.
        var inFlight: Set<String> = []
        var periodicUploads: Task<Void, Never>? = nil
    }

    /// File reader providing data to upload. Not thread safe — every access goes
    /// through `readerLock`.
    private let fileReader: FileReader
    private let readerLock = UnfairLock()
    /// Data uploader sending data to server.
    private let dataUploader: DataUploaderType
    /// Name of the feature this worker is performing uploads for.
    private let featureName: String
    /// Request timeout for upload
    private let uploadTimeout: TimeInterval
    /// Optional telemetry observer notified about upload attempts / drops.
    private let observer: UploadObserver?
    /// Logger for upload status and errors.
    private let log: Logger
    private let state: Synced<State>

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
        self.uploadTimeout = uploadTimeout
        self.observer = observer
        self.log = log
        self.featureName = featureName
        self.state = Synced(State(delay: delay))

        let task = Task<Void, Never>.detached(priority: priority.taskPriority) { [weak self] in
            await self?.runPeriodicUploads()
        }
        state.update { $0.periodicUploads = task }
    }

    func update(dataFormat: DataFormatType) {
        readerLock.whileLocked { fileReader.update(dataFormat: dataFormat) }
    }

    // MARK: - Periodic uploads

    private func runPeriodicUploads() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: state.value.delay.current.nanoseconds)
            } catch {
                return // cancelled
            }
            guard !state.value.isStopped else { return }
            await uploadNextBatch()
        }
    }

    private func uploadNextBatch() async {
        guard let batch = claimNextBatch() else {
            state.update { $0.delay.increase() }
            return
        }
        defer { release(batch) }
        if await upload(data: batch.data, timeout: uploadTimeout) == .success {
            try? markAsRead(batch)
        }
    }

    // MARK: - Flush

    /// Drains all pending batches synchronously.
    ///
    /// `timeout`, when set, is a total wall-clock budget for the whole drain:
    /// once it elapses no further attempt is started and remaining batches are
    /// left on disk for a later run. Each individual attempt is additionally
    /// bounded by the smaller of the remaining budget and the default
    /// per-attempt cap.
    func flush(timeout: TimeInterval?) throws -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout ?? uploadTimeout)
        var result = true
        var iterator = try remainingBatches()
        batchLoop: while let batchRes = iterator.next() {
            guard case .success(let batch) = batchRes else {
                result = false
                break
            }
            // Skip a batch the periodic loop is already uploading.
            guard claim(batch) else { continue }
            defer { release(batch) }
            var status: UploadResult
            repeat {
                guard let attemptTimeout = attemptTimeout(until: deadline) else {
                    result = false
                    break batchLoop
                }
                status = upload(data: batch.data, timeout: attemptTimeout)
                switch status {
                case .success:
                    try markAsRead(batch)
                    result = true
                case .failed:
                    result = false
                case .retry:
                    Thread.sleep(forTimeInterval: retryDelay(until: deadline))
                }
            } while status.isRetry
            guard result else { break }
        }
        return result
    }

    func flush(timeout: TimeInterval?) async throws -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout ?? uploadTimeout)
        var result = true
        var iterator = try remainingBatches()
        batchLoop: while let batchRes = iterator.next() {
            guard case .success(let batch) = batchRes else {
                result = false
                break
            }
            guard claim(batch) else { continue }
            defer { release(batch) }
            var status: UploadResult
            repeat {
                guard let attemptTimeout = attemptTimeout(until: deadline) else {
                    result = false
                    break batchLoop
                }
                status = await upload(data: batch.data, timeout: attemptTimeout)
                switch status {
                case .success:
                    try markAsRead(batch)
                    result = true
                case .failed:
                    result = false
                case .retry:
                    try? await Task.sleep(nanoseconds: retryDelay(until: deadline).nanoseconds)
                }
            } while status.isRetry
            guard result else { break }
        }
        return result
    }

    // MARK: - Stop

    func stop() {
        // Cancellation is enough: `isStopped` blocks any further claim, and
        // `inFlight` keeps a still-finishing cycle from colliding with a flush.
        // We deliberately don't await the task — that would make teardown depend
        // on the cooperative executor being scheduled.
        cancelPeriodicUploads()?.cancel()
    }

    func stop() async {
        guard let task = cancelPeriodicUploads() else { return }
        task.cancel()
        await task.value
    }

    private func cancelPeriodicUploads() -> Task<Void, Never>? {
        state.update { state in
            state.isStopped = true
            defer { state.periodicUploads = nil }
            return state.periodicUploads
        }
    }

    // MARK: - Batch bookkeeping

    private func remainingBatches() throws -> Batch.Iterator {
        try readerLock.whileLocked { try fileReader.getRemainingBatches() }
    }

    /// Reads the next batch and claims it for upload, or returns `nil` when
    /// there is nothing to upload (or it's already claimed).
    private func claimNextBatch() -> Batch? {
        let batch = readerLock.whileLocked { try? fileReader.getNextBatch() }
        guard let batch, claim(batch) else { return nil }
        return batch
    }

    /// Claims a batch unless another upload already holds it. Deliberately does
    /// not consider `isStopped`: `stop()` is followed by a final `flush()` on the
    /// shutdown path, and that flush still has to drain everything.
    private func claim(_ batch: Batch) -> Bool {
        state.update { state in
            guard !state.inFlight.contains(batch.file.name) else { return false }
            state.inFlight.insert(batch.file.name)
            return true
        }
    }

    private func release(_ batch: Batch) {
        state.update { $0.inFlight.remove(batch.file.name) }
    }

    private func markAsRead(_ batch: Batch) throws {
        try readerLock.whileLocked { try fileReader.markBatchAsRead(batch) }
    }

    /// Remaining per-attempt budget, or `nil` when the total flush budget is
    /// exhausted and remaining batches should be left on disk.
    private func attemptTimeout(until deadline: Date) -> TimeInterval? {
        let remaining = max(0, deadline.timeIntervalSinceNow)
        guard remaining > 0 else {
            log.print("[\(featureName)] flush timed out; leaving remaining batches on disk")
            return nil
        }
        return remaining
    }

    /// Backoff before the next retry attempt, never past the flush deadline.
    private func retryDelay(until deadline: Date) -> TimeInterval {
        min(state.value.delay.current, max(0, deadline.timeIntervalSinceNow))
    }

    // MARK: - Upload

    private func upload(data: Data, timeout: TimeInterval?) -> UploadResult {
        let start = observer != nil ? DispatchTime.now() : nil
        let status = dataUploader.upload(data: data, timeout: timeout)
        return finish(status: status, byteCount: data.count, start: start)
    }

    private func upload(data: Data, timeout: TimeInterval?) async -> UploadResult {
        let start = observer != nil ? DispatchTime.now() : nil
        let status = await dataUploader.upload(data: data, timeout: timeout)
        return finish(status: status, byteCount: data.count, start: start)
    }

    /// Maps an upload status to a `UploadResult`, updating the backoff delay and
    /// reporting the attempt. Shared by both `upload` overloads.
    private func finish(status: DataUploadStatus, byteCount: Int, start: DispatchTime?) -> UploadResult {
        let result: UploadResult = state.update { state in
            guard status.needsRetry else {
                state.delay.decrease()
                return .success
            }
            guard let waitTime = status.waitTime else {
                state.delay.increase()
                return .retry
            }
            return state.delay.set(delay: waitTime) ? .retry : .failed
        }
        switch result {
        case .success:
            log.debug("[\(featureName)] batch uploaded (\(byteCount) bytes)")
        case .retry:
            let reason = status.failureDescription.map { ": \($0)" } ?? ""
            log.print("[\(featureName)] upload failed, will retry\(reason)")
        case .failed:
            let reason = status.failureDescription.map { ": \($0)" } ?? ""
            log.print("[\(featureName)] upload failed, dropping batch\(reason)")
        }
        if let observer, let start {
            let durationMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            observer.uploadAttempt(payloadBytes: byteCount, durationMs: durationMs,
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

private extension TimeInterval {
    var nanoseconds: UInt64 { UInt64(max(0, self) * 1_000_000_000) }
}

private extension DispatchQoS {
    var taskPriority: TaskPriority {
        switch qosClass {
        case .userInteractive: return .high
        case .userInitiated: return .userInitiated
        case .utility: return .utility
        case .background: return .background
        default: return .medium
        }
    }
}
