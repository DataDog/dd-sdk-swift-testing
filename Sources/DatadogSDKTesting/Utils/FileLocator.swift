/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

struct FunctionInfo: Sendable {
    let file: String
    let startLine: Int
    private(set) var endLine: Int

    mutating func updateWithLine(_ line: Int) {
        if endLine < line {
            endLine = line
        }
    }
}

typealias FunctionName = String
typealias FunctionMap = [FunctionName: FunctionInfo]

enum FileLocator {
    private enum DeclKind { case ext, objc }

    static func extractFunctions(_ symbolsOutput: URL) throws -> FunctionMap {
        var map = FunctionMap()
        var trackedKeys: Set<String> = []
        var activeKey: String? = nil
        /// True while the active key's own declaration chunk is still supplying its first
        /// source line — that line replaces any previously recorded range (last-wins).
        var activeIsFreshDeclaration = false
        var pendingModuleless: String? = nil

        let file = DDFileReader(fileURL: symbolsOutput)
        try file.open()
        defer { file.close() }

        while let line = try file.readLine() {
            if line.contains(" __TEXT __text") { break }
        }

        while var line = try file.readLine() {
            let reachedStubs: Bool = line.withUTF8 { buf in
                var end = buf.count
                let hasNewline = end > 0 && buf[end - 1] == UInt8(ascii: "\n")
                if hasNewline { end -= 1 }
                guard end > 0 else { return false }

                // Symbol header: "<indent>0xADDR (<pad>0xSIZE) <name> [FLAGS] "
                if hasNewline, end >= 2,
                   buf[end - 1] == UInt8(ascii: " "), buf[end - 2] == UInt8(ascii: "]")
                {
                    activeKey = nil
                    activeIsFreshDeclaration = false
                    pendingModuleless = nil
                    guard let nameStart = Self.indexAfterPrefix(buf, end),
                          let funcAt = Self.find(buf, from: nameStart, to: end, needle: "[FUNC,"),
                          case let flagsStart = funcAt + 6,
                          case let flagsEnd = end - 2, // index of the closing "]"
                          flagsStart <= flagsEnd,
                          buf[funcAt - 1] == UInt8(ascii: " ")
                    else { return false }
                    var nameEnd = funcAt
                    while nameEnd > nameStart, buf[nameEnd - 1] == UInt8(ascii: " ") { nameEnd -= 1 }
                    guard nameEnd > nameStart else { return false }

                    if let kind = Self.declKind(buf, flagsStart, flagsEnd),
                       Self.isDeclarationName(buf, nameStart, nameEnd)
                    {
                        switch kind {
                        case .ext:
                            // key == name with any trailing "()" removed; the module prefix is
                            // present iff a "." occurs before the first backtick.
                            let keyEnd = Self.droppingCallParens(buf, nameStart, nameEnd)
                            if Self.hasModulePrefix(buf, nameStart, keyEnd) {
                                let key = Self.string(buf, nameStart, keyEnd)
                                trackedKeys.insert(key)
                                activeKey = key
                                activeIsFreshDeclaration = true
                            } else {
                                pendingModuleless = Self.string(buf, nameStart, keyEnd)
                            }
                        case .objc:
                            // "-[Class selector]" -> "Class.selector"
                            let innerStart = nameStart + 2, innerEnd = nameEnd - 1
                            guard let sep = Self.firstIndex(buf, innerStart, innerEnd, UInt8(ascii: " ")),
                                  sep > innerStart, sep + 1 < innerEnd,
                                  Self.firstIndex(buf, sep + 1, innerEnd, UInt8(ascii: " ")) == nil,
                                  Self.hasPrefix(buf, sep + 1, innerEnd, "test")
                            else { return false }
                            let key = Self.string(buf, innerStart, sep) + "."
                                + Self.string(buf, sep + 1, innerEnd)
                            trackedKeys.insert(key)
                            activeKey = key
                            activeIsFreshDeclaration = true
                        }
                    } else if !trackedKeys.isEmpty {
                        // A compiler-generated layer over some function's body (`@objc `,
                        // `specialized `, `closure #N in `, `partial apply for `, or none at
                        // all). If it names a function we track, it continues that function.
                        let bodyStart = Self.skippingWrapperPrefixes(buf, nameStart, nameEnd)
                        let keyEnd = Self.droppingCallParens(buf, bodyStart, nameEnd)
                        guard keyEnd > bodyStart else { return false }
                        let candidate = Self.string(buf, bodyStart, keyEnd)
                        if trackedKeys.contains(candidate) { activeKey = candidate }
                    }
                    return false
                }

                // Zero addresses carry no usable line information.
                if hasNewline, end >= 2,
                   buf[end - 2] == UInt8(ascii: ":"), buf[end - 1] == UInt8(ascii: "0")
                { return false }

                if activeKey != nil || pendingModuleless != nil,
                   let source = Self.sourceLine(buf, end)
                {
                    let lineNumber = source.line
                    if let function = pendingModuleless {
                        let filePath = Self.string(buf, source.fileStart, source.fileEnd)
                        let url = URL(fileURLWithPath: filePath, isDirectory: false)
                        let key = "[\(url.deletingPathExtension().lastPathComponent)].\(function)"
                        trackedKeys.insert(key)
                        map[key] = FunctionInfo(file: filePath, startLine: lineNumber, endLine: lineNumber)
                        activeKey = key
                        activeIsFreshDeclaration = false
                        pendingModuleless = nil
                    } else if let key = activeKey {
                        if activeIsFreshDeclaration {
                            // A fresh declaration replaces whatever an earlier same-named
                            // declaration recorded, rather than widening its range.
                            map[key] = FunctionInfo(file: Self.string(buf, source.fileStart, source.fileEnd),
                                                    startLine: lineNumber, endLine: lineNumber)
                            activeIsFreshDeclaration = false
                        } else if var info = map[key] {
                            if Self.matches(buf, source.fileStart, source.fileEnd, info.file) {
                                info.updateWithLine(lineNumber)
                                map[key] = info
                            }
                        } else if !Self.isSyntheticSource(buf, source.fileStart, source.fileEnd) {
                            // Only a continuation chunk pointing at real source may establish
                            // the function's file: compiler-generated and macro-expansion
                            // buffers would otherwise be reported as the test's location.
                            map[key] = FunctionInfo(file: Self.string(buf, source.fileStart, source.fileEnd),
                                                    startLine: lineNumber, endLine: lineNumber)
                        }
                    }
                    return false
                }

                if hasNewline, Self.hasSuffix(buf, end, "__TEXT __stubs") { return true }
                return false
            }
            if reachedStubs { break }
        }

        return map
    }

    static func testFunctionsInModule(_ module: String) throws -> FunctionMap {
        guard let symbolsFile = DDSymbolicator.symbolsInfo(forLibrary: module) else {
            return FunctionMap()
        }
        defer { try? FileManager.default.removeItem(at: symbolsFile) }

        return try extractFunctions(symbolsFile)
    }

    // MARK: - Byte-level parsing helpers
    //
    // `symbols` emits a rigid ASCII layout, and this runs over every line of a dump that can
    // reach tens of megabytes, so the scanning is done on UTF-8 bytes. Swift's `Character`
    // view performs grapheme breaking, which dominates the runtime of the naive spelling.

    /// Index just past the first `") "`, which always terminates the address/size prefix
    /// (neither field can contain a parenthesis).
    private static func indexAfterPrefix(_ b: UnsafeBufferPointer<UInt8>, _ end: Int) -> Int? {
        var i = 0
        while i + 1 < end {
            if b[i] == UInt8(ascii: ")"), b[i + 1] == UInt8(ascii: " ") { return i + 2 }
            i += 1
        }
        return nil
    }

    private static func find(_ b: UnsafeBufferPointer<UInt8>, from: Int, to: Int, needle: StaticString) -> Int? {
        let n = needle.utf8CodeUnitCount
        guard n > 0, to - from >= n else { return nil }
        let first = needle.utf8Start[0]
        var i = from
        while i + n <= to {
            if b[i] == first {
                var k = 1
                while k < n, b[i + k] == needle.utf8Start[k] { k += 1 }
                if k == n { return i }
            }
            i += 1
        }
        return nil
    }

    private static func firstIndex(_ b: UnsafeBufferPointer<UInt8>, _ from: Int, _ to: Int, _ byte: UInt8) -> Int? {
        var i = from
        while i < to {
            if b[i] == byte { return i }
            i += 1
        }
        return nil
    }

    private static func hasPrefix(_ b: UnsafeBufferPointer<UInt8>, _ from: Int, _ to: Int, _ p: StaticString) -> Bool {
        let n = p.utf8CodeUnitCount
        guard to - from >= n else { return false }
        var k = 0
        while k < n {
            if b[from + k] != p.utf8Start[k] { return false }
            k += 1
        }
        return true
    }

    private static func hasSuffix(_ b: UnsafeBufferPointer<UInt8>, _ end: Int, _ s: StaticString) -> Bool {
        let n = s.utf8CodeUnitCount
        guard end >= n else { return false }
        return hasPrefix(b, end - n, end, s)
    }

    private static func string(_ b: UnsafeBufferPointer<UInt8>, _ from: Int, _ to: Int) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: b[from..<to]), as: UTF8.self)
    }

    private static func matches(_ b: UnsafeBufferPointer<UInt8>, _ from: Int, _ to: Int, _ s: String) -> Bool {
        var s = s
        return s.withUTF8 { other in
            guard other.count == to - from else { return false }
            var k = 0
            while k < other.count {
                if b[from + k] != other[k] { return false }
                k += 1
            }
            return true
        }
    }

    /// `EXT`/`OBJC` must be the first flag after `FUNC`, and the remaining flags must be a
    /// non-empty run of word/space/comma bytes (so `OMIT-FP` disqualifies the entry).
    private static func declKind(_ b: UnsafeBufferPointer<UInt8>, _ from: Int, _ to: Int) -> DeclKind? {
        var i = from
        while i < to, b[i] == UInt8(ascii: " ") { i += 1 }
        guard i > from else { return nil } // whitespace is required after "FUNC,"
        let kind: DeclKind
        if hasPrefix(b, i, to, "EXT") {
            kind = .ext
            i += 3
        } else if hasPrefix(b, i, to, "OBJC") {
            kind = .objc
            i += 4
        } else {
            return nil
        }
        guard i < to else { return nil }
        while i < to {
            let c = b[i]
            let isWord = (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z"))
                || (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z"))
                || (c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9"))
                || c == UInt8(ascii: "_")
            guard isWord || c == UInt8(ascii: ",") || c == UInt8(ascii: " ") else { return nil }
            i += 1
        }
        return kind
    }

    /// A declaration is named either as an ObjC method (`-[Class selector:]`) or as a Swift
    /// symbol with no whitespace outside backtick-quoted segments. Anything else (`static
    /// Foo.bar.getter`, `variable initialization expression of …`) is not a declaration.
    private static func isDeclarationName(_ b: UnsafeBufferPointer<UInt8>, _ from: Int, _ to: Int) -> Bool {
        if to - from > 3, b[from] == UInt8(ascii: "-"), b[from + 1] == UInt8(ascii: "["),
           b[to - 1] == UInt8(ascii: "]")
        {
            var i = from + 2
            while i < to - 1 {
                let c = b[i]
                let ok = (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z"))
                    || (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z"))
                    || (c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9"))
                    || c == UInt8(ascii: "_") || c == UInt8(ascii: " ") || c == UInt8(ascii: ":")
                    || c == UInt8(ascii: "$") || c == UInt8(ascii: "#")
                guard ok else { return false }
                i += 1
            }
            return true
        }
        var insideBackticks = false
        var i = from
        while i < to {
            let c = b[i]
            if c == UInt8(ascii: "`") {
                insideBackticks = !insideBackticks
            } else if !insideBackticks, c == UInt8(ascii: " ") || c == UInt8(ascii: "\t") {
                return false
            }
            i += 1
        }
        return !insideBackticks
    }

    /// A module/type prefix is present iff a "." occurs before the first backtick (a
    /// backtick-quoted name may itself contain dots, e.g. ``test 3.0 behavior``).
    private static func hasModulePrefix(_ b: UnsafeBufferPointer<UInt8>, _ from: Int, _ to: Int) -> Bool {
        var i = from
        while i < to, b[i] != UInt8(ascii: "`") {
            if b[i] == UInt8(ascii: ".") { return true }
            i += 1
        }
        return false
    }

    private static func droppingCallParens(_ b: UnsafeBufferPointer<UInt8>, _ from: Int, _ to: Int) -> Int {
        if to - from >= 2, b[to - 2] == UInt8(ascii: "("), b[to - 1] == UInt8(ascii: ")") { return to - 2 }
        return to
    }

    private static func skippingWrapperPrefixes(_ b: UnsafeBufferPointer<UInt8>, _ from: Int, _ to: Int) -> Int {
        var i = from
        while i < to {
            if hasPrefix(b, i, to, "@objc ") { i += 6; continue }
            if hasPrefix(b, i, to, "specialized ") { i += 12; continue }
            if hasPrefix(b, i, to, "partial apply for ") { i += 18; continue }
            if hasPrefix(b, i, to, "closure #") {
                var j = i + 9
                let digitsStart = j
                while j < to, b[j] >= UInt8(ascii: "0"), b[j] <= UInt8(ascii: "9") { j += 1 }
                if j > digitsStart, hasPrefix(b, j, to, " in ") { i = j + 4; continue }
            }
            break
        }
        return i
    }

    /// Splits a source-location line into its file-path byte range and line number.
    private static func sourceLine(_ b: UnsafeBufferPointer<UInt8>, _ end: Int)
        -> (fileStart: Int, fileEnd: Int, line: Int)?
    {
        guard var i = indexAfterPrefix(b, end) else { return nil }
        while i < end, b[i] == UInt8(ascii: " ") { i += 1 }
        // The line number follows the last ":" and must be all digits.
        var colon = -1
        var k = end - 1
        while k >= i {
            if b[k] == UInt8(ascii: ":") { colon = k; break }
            k -= 1
        }
        guard colon > 0, colon + 1 < end else { return nil }
        var value = 0
        var d = colon + 1
        while d < end {
            let c = b[d]
            guard c >= UInt8(ascii: "0"), c <= UInt8(ascii: "9") else { return nil }
            value = value * 10 + Int(c - UInt8(ascii: "0"))
            d += 1
        }
        return (fileStart: i, fileEnd: colon, line: value)
    }

    /// `/<compiler-generated>`, `<stdin>` and macro-expansion buffers under
    /// `swift-generated-sources` are not real source locations.
    private static func isSyntheticSource(_ b: UnsafeBufferPointer<UInt8>, _ from: Int, _ to: Int) -> Bool {
        var basename = from
        var i = from
        while i < to {
            if b[i] == UInt8(ascii: "/") { basename = i + 1 }
            i += 1
        }
        if basename < to, b[basename] == UInt8(ascii: "<") { return true }
        return find(b, from: from, to: to, needle: "swift-generated-sources") != nil
    }
}
