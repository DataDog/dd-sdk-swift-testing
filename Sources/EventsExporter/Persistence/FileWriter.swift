/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal final class FileWriter {
    /// Data writting format.
    private var dataFormat: DataFormatType
    /// Orchestrator producing reference to writable file.
    private let orchestrator: FilesOrchestratorType
    /// JSON encoder used to encode data.
    private let encoder: JSONEncoder
    /// Queue used to synchronize files access (read / write) and perform decoding on background thread.
    private let queue: DispatchQueue
    
    init(entity: String,
         dataFormat: DataFormatType,
         orchestrator: FilesOrchestratorType,
         encoder: JSONEncoder)
    {
        self.dataFormat = dataFormat
        self.orchestrator = orchestrator
        self.encoder = encoder
        self.queue = DispatchQueue(label: "datadogtest.filewriter.\(entity)",
                                   target: .global(qos: .userInteractive))
    }
    
    func update(dataFormat: DataFormatType) {
        queue.sync(flags: .barrier) {
            orchestrator.closeWritableFile()
            self.dataFormat = dataFormat
        }
    }
    
    func closeCurrentFile() {
        queue.sync(flags: .barrier) { orchestrator.closeWritableFile() }
    }

    // MARK: - Writing data

    /// Encodes given value to JSON data and writes it to file.
    func write<T: Encodable>(value: T) -> AsyncResult<Void, any Error> {
        .wrap { res in
            queue.async { [weak self] in
                do {
                    try self?.write(value: value, sync: false)
                    res(.success(()))
                } catch {
                    res(.failure(error))
                }
            }
        }
    }

    func writeSync<T: Encodable>(value: T) throws {
        try queue.sync {
            try write(value: value, sync: true)
        }
    }
    
    private func write<T: Encodable>(value: T, sync: Bool) throws {
        let data = try encoder.encode(value)
        let file = try orchestrator.getWritableFile(writeSize: UInt64(data.count))
        if file.isNew {
            try file.file.append(data: dataFormat.prefix + data, synchronized: sync)
        } else {
            try file.file.append(data: dataFormat.separator + data, synchronized: sync)
        }
    }
}
