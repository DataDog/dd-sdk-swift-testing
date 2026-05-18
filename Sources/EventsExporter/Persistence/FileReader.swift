/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct Batch {
    /// Data read from file (with prefix; suffix is appended below).
    let data: Data
    /// File from which `data` was read.
    let file: ReadableFile
}

extension Batch {
    struct Iterator: IteratorProtocol {
        typealias Element = Result<Batch, any Error>

        private var iterator: Array<ReadableFile>.Iterator
        private let suffix: Data

        init(_ iter: Array<ReadableFile>.Iterator, suffix: Data) {
            self.iterator = iter
            self.suffix = suffix
        }

        mutating func next() -> Element? {
            iterator.next().map { file in
                Result { try Batch(data: file.read() + suffix, file: file) }
            }
        }
    }
}

/// Not thread safe — must be driven from the upload worker's queue.
internal final class FileReader {
    /// Data reading format (header lives in the file itself; we only need the suffix).
    private var dataFormat: DataFormatType
    /// Orchestrator producing reference to readable file.
    private let orchestrator: FilesOrchestratorType

    init(dataFormat: DataFormatType, orchestrator: FilesOrchestratorType) {
        self.dataFormat = dataFormat
        self.orchestrator = orchestrator
    }

    func update(dataFormat: DataFormatType) {
        self.dataFormat = dataFormat
    }

    // MARK: - Reading batches

    func getNextBatch() throws -> Batch? {
        guard let file = try orchestrator.getReadableFile() else {
            return nil
        }
        let data = try file.read()
        return Batch(data: data + dataFormat.suffix, file: file)
    }

    func getRemainingBatches() throws -> Batch.Iterator {
        let files = try orchestrator.getAllReadableFiles()
        return Batch.Iterator(files.makeIterator(), suffix: dataFormat.suffix)
    }

    // MARK: - Accepting batches

    func markBatchAsRead(_ batch: Batch) throws {
        try orchestrator.delete(readableFile: batch.file)
    }
}
