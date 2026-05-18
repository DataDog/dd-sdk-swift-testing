/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal protocol DataFormatType {
    var prefix: Data { get }
    var suffix: Data { get }
    var separator: Data { get }
}

internal protocol JSONFileHeader: Encodable {
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

    /// Builds a `{ ...header..., "<batch>": [ ... ] }` envelope around the
    /// written entities. The header is encoded once at init; the writer prepends
    /// `prefix` before the first entity and appends `suffix` after the last.
    init<H: JSONFileHeader>(header: H, encoder: JSONEncoder) throws {
        var headerData = try encoder.encode(header)
        // Replace closing `}` with `,` then append the array opener so the
        // batch entities slot in as the value of `batchFieldName`.
        headerData[headerData.count - 1] = UInt8(ascii: ",")
        headerData.append(contentsOf: "\"\(H.batchFieldName)\":[".utf8)
        self.init(prefix: headerData,
                  suffix: Data("]}".utf8),
                  separator: Data(",".utf8))
    }

    static var jsonArray: Self {
        .init(prefix: Data("[".utf8),
              suffix: Data("]".utf8),
              separator: Data(",".utf8))
    }
}
