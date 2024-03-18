/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal final class FileWriter {
    /// Data writting format.
    private let dataFormat: DataFormat
    /// Orchestrator producing reference to writable file.
    private let orchestrator: FilesOrchestrator
    /// JSON encoder used to encode data.
    private let jsonEncoder: JSONEncoder
    /// Queue used to synchronize files access (read / write) and perform decoding on background thread.
    internal let queue = DispatchQueue(label: "civisibility.filewriter", target: .global(qos: .userInteractive))

    init(dataFormat: DataFormat, orchestrator: FilesOrchestrator) {
        self.dataFormat = dataFormat
        self.orchestrator = orchestrator
        self.jsonEncoder = JSONEncoder.default()
    }

    // MARK: - Writing data

    /// Encodes given value to JSON data and writes it to file.
    /// Comma is used to separate consecutive values in the file.

    func write<T: Encodable>(value: T) {
        queue.async { [weak self] in
            Log.print("Writing value: \(value)")
            if self == nil {
                Log.print("ERROR: SELF IS NIL!!!!")
            }
            self?.synchronizedWrite(value: value)
        }
    }

    func writeSync<T: Encodable>(value: T) {
        queue.sync { [weak self] in
            self?.synchronizedWrite(value: value, syncOnEnd: true)
        }
    }

    private func synchronizedWrite<T: Encodable>(value: T, syncOnEnd: Bool = false) {
        do {
            let data = try jsonEncoder.encode(value)
            let file = try orchestrator.getWritableFile(writeSize: UInt64(data.count))

            if try file.size() == 0 {
                try file.append(data: data, synchronized: syncOnEnd)
            } else {
                let atomicData = dataFormat.separatorData + data
                try file.append(data: atomicData, synchronized: syncOnEnd)
            }
            Log.print("Wrote to file: \(value)")
        } catch {
            Log.print("🔥 Failed to write file: \(error)")
        }
    }
}
