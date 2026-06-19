/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// Combines a feature's `FileWriter` with the background `DataUploadWorker` that
/// drains its files. Forwards `update(dataFormat:)` to both so writer and uploader
/// stay in lockstep when the header changes.
internal struct FeatureStoreAndUpload: DataUploadWorkerType {
    let uploader: DataUploadWorkerType
    let writer: FileWriter

    init(
        featureName: String,
        reader: FileReader,
        writer: FileWriter,
        performance: UploadPerformancePreset,
        uploader: DataUploaderType,
        log: Logger,
        observer: UploadObserver? = nil
    ) {
        self.init(
            uploader: DataUploadWorker(
                fileReader: reader,
                dataUploader: uploader,
                delay: DataUploadDelay(performance: performance),
                featureName: featureName,
                priority: performance.uploadQueuePriority,
                log: log,
                observer: observer
            ),
            writer: writer
        )
    }

    init(uploader: DataUploadWorkerType, writer: FileWriter) {
        self.uploader = uploader
        self.writer = writer
    }

    func update(dataFormat: DataFormatType) {
        writer.update(dataFormat: dataFormat)
        uploader.update(dataFormat: dataFormat)
    }

    func write<T: Encodable>(value: T) {
        writer.write(value: value)
    }

    func writeSync<T: Encodable>(value: T) throws {
        try writer.writeSync(value: value)
    }

    /// Drain the writer queue, close the in-progress file, then synchronously
    /// upload everything left on disk.
    func flush() throws -> Bool {
        writer.closeCurrentFile()
        return try uploader.flush()
    }

    /// Shutdown sequence:
    /// 1. Stop scheduling background uploads, so the periodic worker can't run a
    ///    read+upload cycle concurrently with the seal / final flush — the final
    ///    `flush()` is then the only thing touching files during teardown.
    /// 2. Seal the writer: drains in-flight writes and blocks new ones, so by the
    ///    time the flush enumerates the directory no file is mid-write (none can
    ///    be hidden in `activeWrites`) — nothing written so far is skipped.
    /// 3. Synchronously upload everything left on disk.
    func stop() {
        uploader.stop()
        writer.stop()
        _ = try? uploader.flush()
    }
}
