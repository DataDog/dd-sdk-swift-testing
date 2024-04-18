/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

extension Array where Element: StringProtocol {
    public func withCStringsArray<R>(_ body: ([UnsafePointer<CChar>]) throws -> R) rethrows -> R {
        let utf8s = self.map { $0.utf8 }
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: utf8s.reduce(0) { $0 + $1.count + 1 })
        defer { buffer.deallocate() }
        var start = buffer
        let ptrs = utf8s.map {
            var str = $0.withContiguousStorageIfAvailable {
                $0.withMemoryRebound(to: CChar.self) {
                    start.initialize(from: $0.baseAddress!, count: $0.count)
                    return UnsafePointer(start)
                }
            }
            if str != nil {
                start += $0.count
            } else {
                str = UnsafePointer(start)
                $0.forEach {
                    start.initialize(to: CChar(bitPattern: $0))
                    start += 1
                }
            }
            start.initialize(to: 0)
            start += 1
            return str!
        }
        return try body(ptrs)
    }
    
    public func withCStringsNilTerminatedArray<R>(_ body: ([UnsafeMutablePointer<CChar>?]) throws -> R) rethrows -> R {
        try withCStringsArray { ptrs in
            var nptrs: [UnsafeMutablePointer<CChar>?] = []
            nptrs.reserveCapacity(ptrs.count + 1)
            for ptr in ptrs {
                nptrs.append(UnsafeMutablePointer(mutating: ptr))
            }
            nptrs.append(nil)
            return try body(nptrs)
        }
    }
}
