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
        let funcNamePattern = #"(?:-\[[\w \:\$#]+\])|(?:(?:`[^`]*`|[^\s`])+)"#
        let funcRegex = try NSRegularExpression(pattern: #"^\s+[0-9a-fA-FxX]+\s+\([0-9a-fA-FxX\ ]+\)\s+(\#(funcNamePattern))\s+\[FUNC,\s+((?:EXT)|(?:OBJC))[\w\s,]+\] $"#)
        // Looser match used only to attribute a wrapper/continuation chunk (no EXT/OBJC tag)
        // back to an already-tracked function. Unlike `funcNamePattern`, it captures the whole
        // name verbatim — including any embedded spaces from a compiler-added prefix — so it
        // can be stripped by `stripWrapperPrefixes` below.
        let anyFuncRegex = try NSRegularExpression(pattern: #"^\s+[0-9a-fA-FxX]+\s+\([0-9a-fA-FxX\ ]+\)\s+(.+?)\s+\[FUNC,"#)
        let lineRegex = try NSRegularExpression(pattern: #"^\s+[0-9a-fA-FxX]+\s+\([0-9a-fA-FxX\ ]+\)\s+(.*?)\:(\d+)$"#)
        // Compiler-generated wrapper layers around a function's real body carry the original
        // name plus a leading label (`@objc `, `specialized `, `closure #1 in `, `partial apply
        // for `, or a combination of those). Stripping them lets a wrapper/continuation DWARF
        // entry — which never carries its own EXT/OBJC tag — be matched back to the tracked
        // function it belongs to, however far from it it landed in the binary.
        let wrapperPrefixRegex = try NSRegularExpression(
            pattern: #"^(?:partial apply for |@objc |specialized |closure #\d+ in )"#
        )
        let trimCharacters = CharacterSet(charactersIn: "-[]")

        // Find function region
        while let line = try file.readLine() {
            if line.contains(" __TEXT __text") {
                break
            }
        }

        while let line = try file.readLine() {
            if line.hasSuffix("] \n") {
                activeKey = nil
                pendingModuleless = nil
                if let match = funcRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                    let name = line[Range(match.range(at: 1), in: line)!]
                    let type = line[Range(match.range(at: 2), in: line)!]
                    switch type {
                    case "EXT":
                        let info = Self.swiftTestName(function: String(name))
                        if let module = info.module {
                            let key = "\(module).\(info.test)"
                            trackedKeys.insert(key)
                            activeKey = key
                        } else {
                            pendingModuleless = info.test
                        }
                    case "OBJC":
                        let parts = name.trimmingCharacters(in: trimCharacters).components(separatedBy: " ")
                        guard parts.count == 2, parts[1].hasPrefix("test") else { continue }
                        let key = "\(parts[0]).\(parts[1])"
                        trackedKeys.insert(key)
                        activeKey = key
                    default: continue
                    }
                } else if let anyMatch = anyFuncRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                    let rawName = String(line[Range(anyMatch.range(at: 1), in: line)!])
                    let info = Self.swiftTestName(function: Self.stripWrapperPrefixes(rawName, using: wrapperPrefixRegex))
                    let key = info.module == nil ? info.test : "\(info.module!).\(info.test)"
                    if trackedKeys.contains(key) {
                        activeKey = key
                    }
                }
            } else if line.hasSuffix(":0\n") { // ignoring zero addresses
                continue
            } else if let match = lineRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                let filePath = String(line[Range(match.range(at: 1), in: line)!])
                guard let lineNumber = Int(line[Range(match.range(at: 2), in: line)!]) else {
                    continue
                }
                if let function = pendingModuleless {
                    let url = URL(fileURLWithPath: filePath, isDirectory: false)
                    let module = "[\(url.deletingPathExtension().lastPathComponent)]"
                    let key = "\(module).\(function)"
                    trackedKeys.insert(key)
                    map[key] = FunctionInfo(file: filePath, startLine: lineNumber, endLine: lineNumber)
                    activeKey = key
                    pendingModuleless = nil
                } else if let key = activeKey {
                    if var info = map[key] {
                        if info.file == filePath {
                            info.updateWithLine(lineNumber)
                            map[key] = info
                        }
                    } else {
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

    private static func stripWrapperPrefixes(_ name: String, using wrapperPrefixRegex: NSRegularExpression) -> String {
        var result = name
        while let match = wrapperPrefixRegex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) {
            result.removeSubrange(Range(match.range, in: result)!)
        }
        return result
    }
}
