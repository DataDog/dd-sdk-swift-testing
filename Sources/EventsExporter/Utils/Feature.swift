/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// Container with dependencies common to all features (Logging, Tracing and RUM).
internal struct FeaturesCommonDependencies {
    let performance: PerformancePreset
    let httpClient: HTTPClient
    let device: Device
    let dateProvider: DateProvider
}

internal struct FeatureStorage {
    /// Writes data to files.
    let writer: FileWriter
    /// Reads data from files.
    let reader: FileReader

    init(writer: FileWriter, reader: FileReader) {
        self.writer = writer
        self.reader = reader
    }
}

internal struct FeatureUpload {
    /// Uploads data to server.
    let uploader: DataUploadWorkerType

    init(
        featureName: String,
        storage: FeatureStorage,
        requestBuilder: RequestBuilder,
        performance: PerformancePreset,
        debug: Bool
    ) {
        let dataUploader = DataUploader(
            httpClient: HTTPClient(debug: debug),
            requestBuilder: requestBuilder
        )

        self.init(
            uploader: DataUploadWorker(
                fileReader: storage.reader,
                dataUploader: dataUploader,
                delay: DataUploadDelay(performance: performance),
                featureName: featureName
            )
        )
    }

    init(uploader: DataUploadWorkerType) {
        self.uploader = uploader
    }
}
