/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

protocol DataFormatType {
    var prefix: Data { get }
    var suffix: Data { get }
    var separator: Data { get }
}

protocol JSONFileHeader: Encodable {
    static var batchFieldName: String { get }
}

/// Describes the format of writing and reading data from files.
internal struct DataFormat: DataFormatType {
    /// Prefixes the batch payload read from file.
    let prefix: Data
    /// Suffixes the batch payload read from file.
    let suffix: Data
    /// Separates entities written to file.
    let separator: Data
    
    // MARK: - Initialization
    
    init(prefix: Data, suffix: Data, separator: Data) {
        self.prefix = prefix
        self.suffix = suffix
        self.separator = separator
    }
    
    init<H: JSONFileHeader>(header: H, encoder: JSONEncoder) throws {
        let separator = ",".data(using: .utf8)!
        let suffix: Data
        let prefix: Data
        
        // Generating json object.
        // Removing last '}'
        // Adding array field for the batch
        var headerData = try encoder.encode(header)
        headerData[headerData.count - 1] = UInt8(ascii: ",")
        headerData.append(contentsOf: "\"\(H.batchFieldName)\":[".utf8)
        prefix = headerData
        suffix = "]}".data(using: .utf8)!
        
        self.init(prefix: prefix, suffix: suffix, separator: separator)
    }
    
    static var jsonArray: Self {
        .init(prefix: "[".data(using: .utf8)!,
              suffix: "]".data(using: .utf8)!,
              separator: ",".data(using: .utf8)!)
    }
}
