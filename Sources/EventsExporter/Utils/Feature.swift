/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct FeatureStoreAndUpload: DataUploadWorkerType {
    /// Uploads data to server.
    let uploader: DataUploadWorkerType
    /// Writer for this feature
    let writer: FileWriter

    init(
        featureName: String,
        reader: FileReader, writer: FileWriter,
        performance: UploadPerformancePreset,
        uploader: DataUploaderType
    ) {
        self.init(
            uploader: DataUploadWorker(
                fileReader: reader,
                dataUploader: uploader,
                delay: DataUploadDelay(performance: performance),
                featureName: featureName,
                priority: performance.uploadQueuePriority
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
    
    func write<T: Encodable>(value: T) -> AsyncResult<Void, any Error> {
        writer.write(value: value)
    }

    func writeSync<T: Encodable>(value: T) throws {
        try writer.writeSync(value: value)
    }
    
    func flush() throws -> Bool {
        writer.closeCurrentFile()
        return try uploader.flush()
    }
    
    func stop() {
        uploader.stop()
    }
}
