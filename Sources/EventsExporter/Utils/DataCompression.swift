/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Compression
import Foundation

extension Data {
    var deflated: Data? {
        return withUnsafeBytes { (urbp: UnsafeRawBufferPointer) in
            let ubp: UnsafeBufferPointer<UInt8> = urbp.bindMemory(to: UInt8.self)
            let up: UnsafePointer<UInt8> = ubp.baseAddress!
            let count = self.count
            // #if swift(>=5.6)
//            return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: count) { destBuffer in
//                let destBytes = compression_encode_buffer(destBuffer.baseAddress!, count, up, count, nil, COMPRESSION_ZLIB)
//                guard destBytes != 0 else { return nil } // Error, or not enough size.
//                return Data(bytes: destBuffer.baseAddress!, count: destBytes)
//            }
            // #else
            let destBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
            defer { destBuffer.deallocate() }
            let destBytes = compression_encode_buffer(destBuffer, count, up, count, nil, COMPRESSION_ZLIB)
            guard destBytes != 0 else { return nil } // Error, or not enough size.
            return Data(bytes: destBuffer, count: destBytes)
            // #endif
        }
    }
}
