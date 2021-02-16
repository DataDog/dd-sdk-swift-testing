/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Compression
import Foundation

extension Array where Element: BinaryFloatingPoint {
    /// The average value of all the items in the array
    var average: Double {
        if self.isEmpty {
            return 0.0
        }
        let sum = self.reduce(0, +)
        return Double(sum) / Double(self.count)
    }
}

extension String {
    func split(by length: Int) -> [String] {
        var startIndex = self.startIndex
        var results = [Substring]()

        while startIndex < self.endIndex {
            let endIndex = self.index(startIndex, offsetBy: length, limitedBy: self.endIndex) ?? self.endIndex
            results.append(self[startIndex ..< endIndex])
            startIndex = endIndex
        }

        return results.map { String($0) }
    }
}

extension Data {
    func zlibDecompress() -> String {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 8192)
        let result = self.subdata(in: 2 ..< self.count).withUnsafeBytes {
            let read = compression_decode_buffer(buffer, 8192, $0.baseAddress!.bindMemory(to: UInt8.self, capacity: 1), self.count - 2, nil, COMPRESSION_ZLIB)
            return String(decoding: Data(bytes: buffer, count: read), as: UTF8.self)
        } as String
        buffer.deallocate()
        return result
    }
}
