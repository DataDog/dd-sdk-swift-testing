/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct Batch {
    /// Data read from file, prefixed with `[` and suffixed with `]`.
    let data: Data
    /// File from which `data` was read.
    fileprivate let file: ReadableFile
}

internal final class FileReader {
    /// Data reading format.
    private let dataFormat: DataFormat
    /// Orchestrator producing reference to readable file.
    private let orchestrator: FilesOrchestrator
    /// Files marked as read.
    private var filesRead: [ReadableFile] = []

    init(dataFormat: DataFormat, orchestrator: FilesOrchestrator) {
        self.dataFormat = dataFormat
        self.orchestrator = orchestrator
    }

    // MARK: - Reading batches

    func readNextBatch() -> Batch? {
        if let file = orchestrator.getReadableFile(excludingFilesNamed: Set(filesRead.map { $0.name })) {
            do {
                let fileData = try file.read()
                let batchData = dataFormat.prefixData + fileData + dataFormat.suffixData
                return Batch(data: batchData, file: file)
            } catch {
                Log.print("Failed to read data from file")
                return nil
            }
        }

        return nil
    }

    /// This method  gets remaining files at once, and process each file after with the block passed.
    /// Currently called from flush method
    func onRemainingBatches(process: (Batch) -> ()) -> Bool {
        do {
            try orchestrator.getAllFiles(excludingFilesNamed: Set(filesRead.map { $0.name }))?.forEach {
                let fileData = try $0.read()
                let batchData = dataFormat.prefixData + fileData + dataFormat.suffixData
                process(Batch(data: batchData, file: $0))
            }
        } catch {
            return false
        }
        return true
    }

    // MARK: - Accepting batches

    func markBatchAsRead(_ batch: Batch) {
        orchestrator.delete(readableFile: batch.file)
        filesRead.append(batch.file)
    }
}
