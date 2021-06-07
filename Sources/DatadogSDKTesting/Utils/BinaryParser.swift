/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

struct BinaryParser {
    private var data: Data
    init(data: Data) {
        self.data = data
    }

    private mutating func parseUInt<Result>(_: Result.Type) throws -> Result
        where Result: UnsignedInteger
    {
        let expected = MemoryLayout<Result>.size
        guard data.count >= expected else { throw InternalError(description: "emptyData") }
        defer { self.data = self.data.dropFirst(expected) }
        return data
            .prefix(expected)
            .reduce(0) { soFar, new in
                (soFar << 8) | Result(new)
            }
    }

    mutating func parseUInt8() throws -> UInt8 {
        try parseUInt(UInt8.self)
    }

    mutating func parseUInt16() throws -> UInt16 {
        try parseUInt(UInt16.self)
    }

    mutating func parseUInt32() throws -> UInt32 {
        try parseUInt(UInt32.self)
    }

    mutating func parseUInt64() throws -> UInt64 {
        try parseUInt(UInt64.self)
    }
}
