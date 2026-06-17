/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// Sink for fully-formed telemetry payloads. `TelemetryExporter` persists each
/// payload to disk for asynchronous upload; tests substitute an in-memory
/// capture to assert on what the producer emitted.
public protocol TelemetryPayloadExporter: AnyObject {
    func export(item: any TelemetryPayload)
    func export(items: [any TelemetryPayload])
    @discardableResult func flush() -> Bool
    func shutdown()
}

public final class TelemetryExporter: TelemetryPayloadExporter {
    let telemetryStorage: FeatureStoreAndUpload
    private let synchronousWrite: Bool

    public init(config: ExporterConfiguration, storage: Directory, api: TelemetryApi) throws {
        self.synchronousWrite = config.performancePreset.synchronousWrite

        let filesOrchestrator = FilesOrchestrator(
            directory: try storage.createSubdirectory(path: "v1"),
            performance: config.performancePreset,
            dateProvider: SystemDateProvider()
        )

        let encoder = api.encoder
        // Entries are stored as a bare comma-separated sequence of JSON objects with no surrounding
        // array brackets or envelope wrapper. TelemetryApi.send(batch:) adds the full message-batch
        // envelope (timestamp, seq_id, application, host) at upload time.
        let dataFormat = DataFormat(prefix: Data(), suffix: Data(), separator: Data(",".utf8))
        let writer = FileWriter(entity: "telemetry",
                                dataFormat: dataFormat,
                                orchestrator: filesOrchestrator,
                                encoder: encoder,
                                log: config.logger)
        let reader = FileReader(dataFormat: dataFormat, orchestrator: filesOrchestrator)
        let uploader = ClosureDataUploader() { (data) async throws(APICallError) -> Void in
            try await api.send(batch: data)
        }
        self.telemetryStorage = FeatureStoreAndUpload(featureName: "telemetry",
                                                      reader: reader,
                                                      writer: writer,
                                                      performance: config.performancePreset,
                                                      uploader: uploader,
                                                      log: config.logger)
    }

    public func export(items: [any TelemetryPayload]) {
        for item in items {
            write(TelemetryMessageBatch.Message(item))
        }
    }

    public func export(item: any TelemetryPayload) {
        write(TelemetryMessageBatch.Message(item))
    }

    @discardableResult
    public func flush() -> Bool {
        (try? telemetryStorage.flush()) ?? false
    }

    public func shutdown() {
        telemetryStorage.stop()
    }

    private func write<T: Encodable>(_ value: T) {
        if synchronousWrite {
            try? telemetryStorage.writeSync(value: value)
        } else {
            telemetryStorage.write(value: value)
        }
    }
}
