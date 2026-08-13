/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

struct FunctionInfo: Sendable {
    let file: String
    private(set) var startLine: Int
    private(set) var endLine: Int

    mutating func updateWithLine(_ line: Int) {
        if startLine > line {
            startLine = line
        }
        if endLine < line {
            endLine = line
        }
    }
}

typealias FunctionName = String
typealias FunctionMap = [FunctionName: FunctionInfo]

enum FileLocator {
    static func extractFunctions(_ symbolsOutput: URL) throws -> FunctionMap {
        var map = FunctionMap()

        // Keys of functions we know are real declarations (an EXT/OBJC-tagged header was seen
        // for them), so later chunks belonging to the same function that carry no EXT/OBJC tag
        // of their own — async continuations, `@objc` thunks, generic `specialized` clones,
        // closures, partial applies — can still be matched back by name and contribute their
        // source lines, no matter where in the file they land.
        var trackedKeys: Set<String> = []
        // The key currently receiving source-line records, if any.
        var activeKey: String? = nil
        // True until the declaration's own chunk has supplied its first source line. That line
        // replaces any range recorded by an earlier same-named declaration rather than widening
        // it: a generic function can be emitted as several distinct declarations, and merging
        // them would report a span covering two different bodies.
        var activeIsFreshDeclaration = false
        // Set right after an EXT header whose name had no module prefix (e.g. a bare global
        // function): the key can't be known until the first real source line reveals the file,
        // from which the synthetic module name is derived.
        var pendingModuleless: FunctionName? = nil

        let file = DDFileReader(fileURL: symbolsOutput)
        try file.open()
        defer { file.close() }

        // A function name is either an ObjC method (`-[Class selector:]`, may contain
        // spaces) or a Swift symbol. A Swift Testing function name can be backtick-quoted
        // and contain spaces (e.g. ``failing parameterized test``(_:)), so a plain `\S+`
        // truncates it at the first space — match backtick-quoted segments as a unit.
        // These stay regexes on purpose: `\w`/`\s` carry ICU's Unicode semantics, and Swift
        // (and ObjC) identifiers may be non-ASCII.
        let funcNamePattern = #"(?:-\[[\w \:\$#]+\])|(?:(?:`[^`]*`|[^\s`])+)"#
        let funcRegex = try NSRegularExpression(pattern: #"^\s+[0-9a-fA-FxX]+\s+\([0-9a-fA-FxX\ ]+\)\s+(\#(funcNamePattern))\s+\[FUNC,\s+((?:EXT)|(?:OBJC))[\w\s,]+\] $"#)
        // Looser match used only to attribute a wrapper/continuation chunk (no EXT/OBJC tag)
        // back to an already-tracked function. Unlike `funcNamePattern`, it captures the whole
        // name verbatim — including any embedded spaces from a compiler-added prefix — so it
        // can be stripped by `strippingWrapperPrefixes` below.
        let anyFuncRegex = try NSRegularExpression(pattern: #"^\s+[0-9a-fA-FxX]+\s+\([0-9a-fA-FxX\ ]+\)\s+(.+?)\s+\[FUNC,"#)
        let trimCharacters = CharacterSet(charactersIn: "-[]")

        // Find function region
        while let line = try file.readLine() {
            if line.contains(" __TEXT __text") {
                break
            }
        }

        while var line = try file.readLine() {
            if line.hasSuffix("] \n") {
                activeKey = nil
                activeIsFreshDeclaration = false
                pendingModuleless = nil
                // Computed once and shared by both header regexes below.
                let range = NSRange(line.startIndex..., in: line)
                if let match = funcRegex.firstMatch(in: line, range: range) {
                    let name = line[Range(match.range(at: 1), in: line)!]
                    let type = line[Range(match.range(at: 2), in: line)!]
                    switch type {
                    case "EXT":
                        let info = Self.swiftTestName(function: String(name))
                        if let module = info.module {
                            let key = "\(module).\(info.test)"
                            trackedKeys.insert(key)
                            activeKey = key
                            activeIsFreshDeclaration = true
                        } else {
                            pendingModuleless = info.test
                        }
                    case "OBJC":
                        let parts = name.trimmingCharacters(in: trimCharacters).components(separatedBy: " ")
                        guard parts.count == 2, parts[1].hasPrefix("test") else { continue }
                        let key = "\(parts[0]).\(parts[1])"
                        trackedKeys.insert(key)
                        activeKey = key
                        activeIsFreshDeclaration = true
                    default: continue
                    }
                } else if !trackedKeys.isEmpty,
                          let anyMatch = anyFuncRegex.firstMatch(in: line, range: range)
                {
                    // The key of a Swift function is its name minus any trailing "()", so the
                    // candidate can be compared without splitting off the module prefix.
                    let rawName = line[Range(anyMatch.range(at: 1), in: line)!]
                    var candidate = Self.strippingWrapperPrefixes(rawName)
                    if candidate.hasSuffix("()") { candidate = candidate.dropLast(2) }
                    if !candidate.isEmpty, trackedKeys.contains(String(candidate)) {
                        activeKey = String(candidate)
                    }
                }
            } else if line.hasSuffix(":0\n") { // ignoring zero addresses
                continue
            } else if activeKey != nil || pendingModuleless != nil,
                      let source = Self.sourceLine(&line)
            {
                let filePath = source.file
                let lineNumber = source.line
                if let function = pendingModuleless {
                    let url = URL(fileURLWithPath: filePath, isDirectory: false)
                    let key = "[\(url.deletingPathExtension().lastPathComponent)].\(function)"
                    trackedKeys.insert(key)
                    map[key] = FunctionInfo(file: filePath, startLine: lineNumber, endLine: lineNumber)
                    activeKey = key
                    activeIsFreshDeclaration = false
                    pendingModuleless = nil
                } else if let key = activeKey {
                    if activeIsFreshDeclaration {
                        map[key] = FunctionInfo(file: filePath, startLine: lineNumber, endLine: lineNumber)
                        activeIsFreshDeclaration = false
                    } else if var info = map[key] {
                        if info.file == filePath {
                            info.updateWithLine(lineNumber)
                            map[key] = info
                        }
                    } else if !Self.isSyntheticSource(filePath) {
                        // Only a continuation chunk pointing at real source may establish the
                        // function's location: compiler-generated and macro-expansion buffers
                        // would otherwise be reported as the test's source file.
                        map[key] = FunctionInfo(file: filePath, startLine: lineNumber, endLine: lineNumber)
                    }
                }
            } else if line.hasSuffix("__TEXT __stubs\n") {
                break
            }
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

    /// Splits a source-location line — `<indent>0xADDR (<pad>0xSIZE) <path>:<line>` — into its
    /// path and line number.
    ///
    /// This one is scanned over UTF-8 bytes rather than matched with a regex: it is the only
    /// form that occurs on *every* line of a dump that can reach tens of megabytes, and the
    /// equivalent `NSRegularExpression` costs ~2.7µs per line (112ms over this repo's own
    /// 41k-line fixture, roughly 90% of the total parse). Nothing here is Unicode-sensitive —
    /// the delimiters and digits are ASCII, and UTF-8 never encodes an ASCII byte inside a
    /// multi-byte character — so the path is carried through verbatim.
    private static func sourceLine(_ line: inout String) -> (file: String, line: Int)? {
        line.withUTF8 { buf -> (file: String, line: Int)? in
            var end = buf.count
            if end > 0, buf[end - 1] == UInt8(ascii: "\n") { end -= 1 }
            // The address and size fields cannot contain a parenthesis, so the first ") "
            // always terminates the prefix.
            var start = 0
            while start + 1 < end,
                  !(buf[start] == UInt8(ascii: ")") && buf[start + 1] == UInt8(ascii: " "))
            {
                start += 1
            }
            guard start + 1 < end else { return nil }
            start += 2
            while start < end, buf[start] == UInt8(ascii: " ") { start += 1 }
            // The line number follows the last ":" and must be all ASCII digits.
            var colon = end
            var i = end - 1
            while i >= start {
                if buf[i] == UInt8(ascii: ":") { colon = i; break }
                i -= 1
            }
            guard colon < end, colon + 1 < end else { return nil }
            var value = 0
            var d = colon + 1
            while d < end {
                let digit = buf[d]
                guard digit >= UInt8(ascii: "0"), digit <= UInt8(ascii: "9") else { return nil }
                value = value * 10 + Int(digit - UInt8(ascii: "0"))
                d += 1
            }
            let path = String(decoding: UnsafeBufferPointer(rebasing: buf[start..<colon]), as: UTF8.self)
            return (file: path, line: value)
        }
    }

    /// `/<compiler-generated>`, `<stdin>` and macro-expansion buffers under
    /// `swift-generated-sources` are not source locations a user can navigate to.
    private static func isSyntheticSource(_ path: String) -> Bool {
        let basename = path.lastIndex(of: "/").map { path[path.index(after: $0)...] } ?? path[...]
        return basename.hasPrefix("<") || path.contains("swift-generated-sources")
    }

    private static func swiftTestName(function name: String) -> (test: String, module: String?) {
        var function: String
        let module: String?
        // The module/type prefix carries no backticks, but a backtick-quoted function
        // name may contain dots (e.g. ``test 3.0``). Split on the last dot that precedes
        // the first backtick, so such a dot isn't mistaken for the module separator.
        let searchEnd = name.firstIndex(of: "`") ?? name.endIndex
        if let dotPos = name[..<searchEnd].lastIndex(of: ".") {
            function = String(name[name.index(after: dotPos)...])
            module = String(name[..<dotPos])
        } else {
            function = String(name)
            module = nil
        }
        if function.hasSuffix("()") {
            function = String(function[..<function.index(function.endIndex, offsetBy: -2)])
        }
        return (test: function, module: module)
    }

    private static let wrapperPrefixes = ["partial apply for ", "@objc ", "specialized "]

    /// Compiler-generated wrapper layers around a function's real body carry the original
    /// name plus a leading label (`@objc `, `specialized `, `closure #1 in `, `partial apply
    /// for `, or a combination of those). Stripping them lets a wrapper/continuation entry —
    /// which never carries its own EXT/OBJC tag — be matched back to the tracked function it
    /// belongs to, however far from it it landed in the binary.
    private static func strippingWrapperPrefixes(_ name: Substring) -> Substring {
        var result = name
        outer: while !result.isEmpty {
            for prefix in Self.wrapperPrefixes where result.hasPrefix(prefix) {
                result = result.dropFirst(prefix.count)
                continue outer
            }
            if result.hasPrefix("closure #") {
                let afterHash = result.dropFirst(9)
                let digits = afterHash.prefix(while: { $0.isNumber })
                let afterDigits = afterHash.dropFirst(digits.count)
                if !digits.isEmpty, afterDigits.hasPrefix(" in ") {
                    result = afterDigits.dropFirst(4)
                    continue outer
                }
            }
            break
        }
        return result
    }
}
