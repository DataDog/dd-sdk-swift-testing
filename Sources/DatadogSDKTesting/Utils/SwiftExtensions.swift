/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
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

    public var separatedByWords: String {
        enum My {
            static let regex = try! NSRegularExpression(pattern: "([A-Z]+)[a-zA-Z]|(?<=_).")
        }

        return My.regex.stringByReplacingMatches(in: self, range: NSRange(0 ..< self.utf16.count), withTemplate: " $0").trimmingCharacters(in: CharacterSet(charactersIn: " "))
    }
}

extension Data {
    func zlibDecompress(minimumSize: Int = 0) -> String {
        let expectedSize = minimumSize < 0x10000 ? 0x10000 : 0x10000
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: expectedSize)
        let result = self.subdata(in: 2 ..< self.count).withUnsafeBytes {
            let read = compression_decode_buffer(buffer, expectedSize, $0.baseAddress!.bindMemory(to: UInt8.self, capacity: 1), self.count - 2, nil, COMPRESSION_ZLIB)
            return String(decoding: Data(bytes: buffer, count: read), as: UTF8.self)
        } as String
        buffer.deallocate()
        return result
    }

    var hexString: String {
        return self.map { String(format: "%02x", $0) }.joined()
    }

    init?(hexString: String) {
        let length = hexString.count / 2
        var data = Data(capacity: length)
        for i in 0 ..< length {
            let j = hexString.index(hexString.startIndex, offsetBy: i * 2)
            let k = hexString.index(j, offsetBy: 2)
            let bytes = hexString[j ..< k]
            if var byte = UInt8(bytes, radix: 16) {
                data.append(&byte, count: 1)
            } else {
                return nil
            }
        }
        self = data
    }
}
