/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

struct FunctionInfo {
    var file: String
    var startLine: Int
    var endLine: Int

    mutating func updateWithLine(_ line: Int) {
        if endLine < line {
            endLine = line
        }
    }
}

typealias FunctionName = String
typealias FunctionMap = [FunctionName: FunctionInfo]

enum FileLocator {
    private static let swiftFunctionRegex = try! NSRegularExpression(pattern: #"(\w+)\.(\w+)"#, options: .anchorsMatchLines)
    private static let objcFunctionRegex = try! NSRegularExpression(pattern: #"-\[(\w+) (\w+)\]"#, options: .anchorsMatchLines)
    private static let pathRegex = try! NSRegularExpression(pattern: #"(\/.*?\.\S*):(\d*)"#, options: .anchorsMatchLines)

    static func testFunctionsInModule(_ module: String) -> FunctionMap {
        var functionMap = FunctionMap()
        guard let symbolsInfo = DDSymbolicator.symbolsInfo(forLibrary: module) else {
            return functionMap
        }

        var currentFunctionName: String?
        symbolsInfo.components(separatedBy: .newlines).lazy.forEach { line in

            if line.contains("[FUNC, EXT, LENGTH") ||
                line.contains("[FUNC, PEXT, LENGTH")
            {
                // Swift exported functions
                if let match = swiftFunctionRegex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) {
                    guard let classNameRange = Range(match.range(at: 1), in: line),
                          let functionRange = Range(match.range(at: 2), in: line),
                          String(line[functionRange]).hasPrefix("test")
                    else {
                        return
                    }
                    currentFunctionName = String(line[classNameRange]) + "." + String(line[functionRange])
                }
            } else if line.contains("[FUNC, OBJC, LENGTH") {
                // ObjC exported functions
                if let match = objcFunctionRegex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) {
                    guard let classNameRange = Range(match.range(at: 1), in: line),
                          let functionRange = Range(match.range(at: 2), in: line),
                          String(line[functionRange]).hasPrefix("test")
                    else {
                        return
                    }
                    currentFunctionName = String(line[classNameRange]) + "." + String(line[functionRange])
                }
            } else if line.contains("[FUNC, ") {
                // Other non exported functions
                currentFunctionName = nil
            } else if let functionName = currentFunctionName {
                // Possibly lines of a exported function
                if let match = pathRegex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) {
                    guard let fileRange = Range(match.range(at: 1), in: line),
                          let lineRange = Range(match.range(at: 2), in: line)
                    else {
                        return
                    }

                    let file = String(line[fileRange])
                    if let line = Int(line[lineRange]), line != 0, !file.isEmpty {
                        if functionMap[functionName]?.file == file {
                            functionMap[functionName]?.updateWithLine(line)
                        } else if functionMap[functionName] == nil {
                            functionMap[functionName] = FunctionInfo(file: file, startLine: line, endLine: line)
                        }
                    }
                }
            }
        }
        return functionMap
    }
}
