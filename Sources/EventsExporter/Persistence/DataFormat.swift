/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// Describes the format of writing and reading data from files.
internal struct DataFormat {
    /// Prefixes the batch payload read from file.
    let prefixData: Data
    /// Suffixes the batch payload read from file.
    let suffixData: Data
    /// Separates entities written to file.
    let separatorData: Data

    // MARK: - Initialization

    init(
        prefix: String,
        suffix: String,
        separator: String
    ) {
        self.prefixData = prefix.data(using: .utf8)! // swiftlint:disable:this force_unwrapping
        self.suffixData = suffix.data(using: .utf8)! // swiftlint:disable:this force_unwrapping
        self.separatorData = separator.data(using: .utf8)! // swiftlint:disable:this force_unwrapping
    }
}

protocol FileWriteFormat {
    func start(file: File) throws
    func add(element data: Data, to file: File) throws
    func end(file: File) throws
}

protocol JSONFileHeader: Encodable {
    static var batchFieldName: String { get }
}

extension APIVoidMeta: JSONFileHeader {
    static var batchFieldName: String { "" }
}

struct JSONFileWriteFormat<Header: JSONFileHeader>: FileWriteFormat {
    let encoder: JSONEncoder
    let prefix: Data
    let suffix: Data
    let separator: Data
    
    init(header: Header, encoder: JSONEncoder) throws {
        self.encoder = encoder
        self.separator = Data([UInt8(ascii: ",")])
        if header is APIVoidValue {
            self.prefix = "[".data(using: .utf8)!
            self.suffix = "]".data(using: .utf8)!
        } else {
            // Generating json object.
            // Removing last '}'
            // Adding array field for the batch
            var headerData = try encoder.encode(header)
            self.suffix = Data([UInt8(ascii: "]"), headerData.last!])
            headerData[headerData.count - 1] = UInt8(ascii: ",")
            headerData.append(contentsOf: "\"\(Header.batchFieldName)\":[".utf8)
            self.prefix = headerData
        }
    }
    
    func start(file: File) throws {
        try file.append(data: prefix, synchronized: true)
    }
    
    func add(element data: Data, to file: File) throws {
        try file.append(data: data + separator)
    }
    
    func end(file: File) throws {
        try file.append(data: suffix, synchronized: true)
    }
}
