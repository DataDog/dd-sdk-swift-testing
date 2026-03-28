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
    enum State {
        case skipping
        case started(function: FunctionName, module: String?)
        case parsing(function: FunctionName, module: String, info: FunctionInfo)
        
        var isParsing: Bool {
            switch self {
            case .skipping: return false
            case .parsing, .started: return true
            }
        }
    }
    
    static func extractFunctions(_ symbolsOutput: URL) throws -> FunctionMap {
        var state: State = .skipping
        var map = FunctionMap()
        let file = DDFileReader(fileURL: symbolsOutput)
        try file.open()
        defer { file.close() }
        
        let funcNamePattern = #"(?:-\[[\w \:\$]+\])|(?:\S+)"#
        let funcRegex = try NSRegularExpression(pattern: #"^\s+[0-9a-fA-FxX]+\s+\([0-9a-fA-FxX\ ]+\)\s+(\#(funcNamePattern))\s+\[FUNC,\s+((?:EXT)|(?:OBJC))[\w\s,]+\] $"#)
        let lineRegex = try NSRegularExpression(pattern: #"^\s+[0-9a-fA-FxX]+\s+\([0-9a-fA-FxX\ ]+\)\s+(.*?)\:(\d+)$"#)
        let trimCharacters = CharacterSet(charactersIn: "-[]")
        
        // Find function region
        while let line = try file.readLine() {
            if line.contains(" __TEXT __text") {
                break
            }
        }
        
        while let line = try file.readLine() {
            if line.hasSuffix("] \n") {
                switch state {
                case .parsing(function: let name, module: let mod, info: let info):
                    map["\(mod).\(name)"] = info
                    state = .skipping
                case .started: state = .skipping
                case .skipping: break
                }
                guard let match = funcRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
                    continue
                }
                let name = line[Range(match.range(at: 1), in: line)!]
                let type = line[Range(match.range(at: 2), in: line)!]
                switch type {
                case "EXT":
                    var function: String
                    let module: String?
                    if let dotPos = name.lastIndex(of: ".") {
                        function = String(name[name.index(after: dotPos)...])
                        module = String(name[..<dotPos])
                    } else {
                        function = String(name)
                        module = nil
                    }
                    if function.hasSuffix("()") {
                        function = String(function[..<function.index(function.endIndex, offsetBy: -2)])
                    }
                    state = .started(function: function, module: module)
                case "OBJC":
                    let parts = name.trimmingCharacters(in: trimCharacters).components(separatedBy: " ")
                    guard parts.count == 2, parts[1].hasPrefix("test") else { continue }
                    state = .started(function: parts[1], module: parts[0])
                default: continue
                }
            } else if line.hasSuffix(":0\n") { // ignoring zero addresses
                continue
            } else if state.isParsing,
                      let match = lineRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line) )
            {
                let filePath = String(line[Range(match.range(at: 1), in: line)!])
                guard let lineNumber = Int(line[Range(match.range(at: 2), in: line)!]) else {
                    continue
                }
                switch state {
                case .started(function: let name, module: var mod):
                    if mod == nil {
                        let url = URL(fileURLWithPath: filePath, isDirectory: false)
                        mod = "[\(url.deletingPathExtension().lastPathComponent)]"
                    }
                    state = .parsing(function: name,
                                     module: mod!,
                                     info: FunctionInfo(file: filePath,
                                                        startLine: lineNumber,
                                                        endLine: lineNumber))
                case .parsing(function: let name, module: let mod, info: var info):
                    if info.file == filePath {
                        info.updateWithLine(lineNumber)
                    }
                    state = .parsing(function: name, module: mod, info: info)
                default: throw InternalError(description: "Function parsing failed. Parser in wrong state \(state)")
                }
            } else if line.hasSuffix("__TEXT __stubs\n") {
                break
            }
        }
        
        if case .parsing(let function, let module, let info) = state {
            map["\(module).\(function)"] = info
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
}
