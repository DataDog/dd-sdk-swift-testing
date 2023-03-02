/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
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
    internal static func extractedFunc(_ symbolsFile: URL) -> FunctionMap {
        var functionMap = FunctionMap()
        var currentFunctionName: String?

        do {
            let file = DDFileReader(fileURL: symbolsFile)
            try file.open()
            defer { file.close() }

            // Find function region
            while let line = try file.readLine() {
                if line.contains(" __TEXT __text") {
                    break
                }
            }

            while let line = try file.readLine() {
                if line.hasSuffix("] \n") {
                    if let funcRange = line.range(of: "[FUNC, ")?.lowerBound {
                        if line[line.index(funcRange, offsetBy: 7)...].hasPrefix("EXT") {
                            //Swift
                            let functionEndIndex = line.index(funcRange, offsetBy: -3)
                            guard let dotIndex = line[...line.index(before: functionEndIndex)].lastIndex(of: "."),
                                  line[line.index(after: dotIndex)...].hasPrefix("test"),
                                  let moduleIndex = line[...line.index(before: dotIndex)].lastIndex(of: " "),
                                  let startLineIndex = line[...moduleIndex].lastIndex(of: ")"),
                                  line.distance(from: startLineIndex, to: moduleIndex) <= 1
                            else {
                                currentFunctionName = nil
                                continue
                            }
                            currentFunctionName = String(line[line.index(after: moduleIndex)...line.index(before: functionEndIndex)])
                        } else if line[line.index(funcRange, offsetBy: 7)...].hasPrefix("OBJC") {
                            // ObjC exported functions
                            let subline = line[...funcRange]
                            guard let functionEndIndex = subline.lastIndex(of: "]"),
                                  let spaceIndex = subline[...subline.index(before: functionEndIndex)].lastIndex(of: " "),
                                  subline[subline.index(after: spaceIndex)...].hasPrefix("test"),
                                  let functionStartIndex = subline[...subline.index(before: functionEndIndex)].lastIndex(of: "[")
                            else {
                                currentFunctionName = nil
                                continue
                            }
                            currentFunctionName = String(subline[subline.index(after: functionStartIndex)...subline.index(before: spaceIndex)]) + "." +
                                String(subline[subline.index(after: spaceIndex)...subline.index(before: functionEndIndex)])
                        } else {
                            currentFunctionName = nil
                            continue
                        }
                        
                    } else {
                        // Other non exported functions
                        currentFunctionName = nil
                    }
                } else if line.hasSuffix(":0\n") {
                    continue
                } else if let functionName = currentFunctionName {
                    guard let colonIndex = line.lastIndex(of: ":"),
                          let lineNumber = Int(line[line.index(after: colonIndex)...line.index(line.endIndex, offsetBy: -2)])
                    else {
                        continue
                    }

                    let file = line[line.index(line.startIndex, offsetBy: 50)...line.index(before: colonIndex)]
                    if functionMap[functionName] == nil {
                        functionMap[functionName] = FunctionInfo(file: String(file), startLine: lineNumber, endLine: lineNumber)
                    } else if functionMap[functionName]!.file == file {
                        functionMap[functionName]?.updateWithLine(lineNumber)
                    }
                } else if line.hasSuffix("__TEXT __stubs\n") {
                    break
                }
            }
        } catch {
            return functionMap
        }

        return functionMap
    }

    static func testFunctionsInModule(_ module: String) -> FunctionMap {
        guard let symbolsFile = DDSymbolicator.symbolsInfo(forLibrary: module) else {
            return FunctionMap()
        }
        defer { try? FileManager.default.removeItem(at: symbolsFile) }

        return extractedFunc(symbolsFile)
    }
}
