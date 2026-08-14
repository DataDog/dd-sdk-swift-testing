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
    /// Returns `true` only if every batch stored when the drain began was
    /// accounted for — uploaded and deleted, or deliberately dropped.
    ///
    /// A drain runs exclusively: it first waits for any upload the periodic loop
    /// has already started, so it can never report success while a batch's fate
    /// is still undecided.
    ///
    /// `timeout` is a total wall-clock budget for the whole drain — including that
    /// wait — (e.g. an OpenTelemetry `forceFlush` timeout). When it elapses,
    /// remaining batches are left on disk for a later run and the result is
    /// `false`. `nil` means "no total budget": each attempt is still bounded by
    /// the default per-attempt cap.
    ///
    /// This overload blocks the calling thread and never suspends, so it stays
    /// usable on the teardown path (see `ClosureDataUploader`).
    func flush(timeout: TimeInterval?) throws -> Bool

    /// Drain all stored data, suspending rather than blocking. Same budget and
    /// exclusivity semantics as the synchronous overload.
    func flush(timeout: TimeInterval?) async throws -> Bool

    /// Cancel scheduled uploads, then wait for an upload the loop has already
    /// started so its batch is either uploaded-and-deleted or left on disk before
    /// returning. The wait is bounded: at process exit the cooperative executor
    /// may never resume the task, and blocking forever there is the very deadlock
    /// this path exists to avoid.
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
        var periodicUploads: Task<Void, Never>? = nil
    }

    /// File reader providing data to upload. Not thread safe — every access goes
    /// through `readerLock`.
    private let fileReader: FileReader
    private let readerLock = UnfairLock()
    /// Serializes uploading, the way the worker's `DispatchQueue` used to: the
    /// periodic loop holds it for one batch, a flush holds it for the whole drain.
    /// Without it a flush could walk past a batch another upload had already read
    /// but not yet deleted, and report success while that batch's outcome — and
    /// the matching file deletion — were still pending.
    private let uploadSlot = DispatchSemaphore(value: 1)
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
        // Skip this tick if a flush holds the slot — it is draining everything
        // anyway, and the loop must not read a batch out from under it.
        guard uploadSlot.wait(timeout: .now()) == .success else { return }
        defer { uploadSlot.signal() }

        guard let batch = nextBatch() else {
            state.update { $0.delay.increase() }
            return
        }
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
        // Take the slot first: once held, no other upload is running, so the
        // enumeration below sees the complete, settled set of stored batches.
        guard acquireUploadSlot(until: deadline) else { return false }
        defer { uploadSlot.signal() }

        var result = true
        var iterator = try remainingBatches()
        batchLoop: while let batchRes = iterator.next() {
            guard case .success(let batch) = batchRes else {
                result = false
                break
            }
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
        guard await acquireUploadSlot(until: deadline) else { return false }
        defer { uploadSlot.signal() }

        var result = true
        var iterator = try remainingBatches()
        batchLoop: while let batchRes = iterator.next() {
            guard case .success(let batch) = batchRes else {
                result = false
                break
            }
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
        guard let task = cancelPeriodicUploads() else { return }
        task.cancel()
        // Wait for a cycle the loop may already be running, so its batch is either
        // uploaded and deleted, or left on disk, before we return — otherwise the
        // final flush that follows could report success over an unsettled batch,
        // and process exit could cut the upload short or duplicate it.
        //
        // We wait on the slot rather than the task: awaiting the task needs the
        // cooperative executor, which isn't guaranteed to run during `exit()`.
        // The wait is bounded for the same reason — if the executor is already
        // gone, the cycle will never finish and blocking forever here is exactly
        // the teardown deadlock this path exists to avoid.
        if uploadSlot.wait(timeout: .now() + uploadTimeout) == .success {
            uploadSlot.signal()
        } else {
            log.print("[\(featureName)] timed out waiting for an in-flight upload during shutdown")
        }
    }

    func stop() async {
        guard let task = cancelPeriodicUploads() else { return }
        task.cancel()
        // Awaiting the task is exact here: when it returns, its cycle has released
        // the slot and finished its bookkeeping.
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

    private func nextBatch() -> Batch? {
        readerLock.whileLocked { try? fileReader.getNextBatch() }
    }

    /// Blocks until the upload slot is free or the drain budget runs out.
    /// Deliberately ignores `isStopped`: `stop()` is followed by a final `flush()`
    /// on the shutdown path, and that flush still has to drain everything.
    private func acquireUploadSlot(until deadline: Date) -> Bool {
        let remaining = max(0, deadline.timeIntervalSinceNow)
        guard uploadSlot.wait(timeout: .now() + remaining) == .success else {
            log.print("[\(featureName)] flush timed out waiting for an in-flight upload; leaving batches on disk")
            return false
        }
        return true
    }

    /// Suspending counterpart: polls rather than blocking a cooperative thread.
    private func acquireUploadSlot(until deadline: Date) async -> Bool {
        while uploadSlot.wait(timeout: .now()) != .success {
            guard deadline.timeIntervalSinceNow > 0 else {
                log.print("[\(featureName)] flush timed out waiting for an in-flight upload; leaving batches on disk")
                return false
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return true
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
