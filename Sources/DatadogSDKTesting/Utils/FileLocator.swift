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
        if startLine > line {
            startLine = line
        } else if endLine < line {
            endLine = line
        }
    }
}

typealias FunctionName = String
typealias FunctionMap = [FunctionName: FunctionInfo]

enum FileLocator {
    /// It returns the file path and line of a test given the test class and test name using atos symbolicator
    static func filePath(forTestClass testClass: UnsafePointer<Int8>, testName: String, library: String) -> String {
        guard let objcClass = objc_getClass(testClass) as? AnyClass else {
            return ""
        }

        var testThrowsError = false
        var method = class_getInstanceMethod(objcClass, Selector(testName))
        if method == nil {
            // Try if the test throws an error
            method = class_getInstanceMethod(objcClass, Selector(testName + "AndReturnError:"))
            if method == nil {
                return ""
            }
            testThrowsError = true
        }

        let imp = method_getImplementation(method!)
        guard let symbol = DDSymbolicator.atosSymbol(forAddress: imp.debugDescription, library: library) else {
            return ""
        }

        let symbolInfo: String
        if symbol.contains("<compiler-generated>") {
            // Test was written in Swift, and this is just the Obj-c wrapper,
            // me must locate the original swift method address in the binary
            let newName = DDSymbolicator.swiftTestMangledName(forClassName: String(cString: testClass), testName: testName, throwsError: testThrowsError)
            if let address = DDSymbolicator.address(forSymbolName: newName, library: library),
               let swiftSymbol = DDSymbolicator.atosSymbol(forAddress: address.debugDescription, library: library)
            {
                symbolInfo = swiftSymbol
            } else {
                symbolInfo = ""
            }
        } else {
            symbolInfo = symbol
        }

        let symbolInfoComponents = symbolInfo.components(separatedBy: CharacterSet(charactersIn: "() ")).filter { !$0.isEmpty }
        return symbolInfoComponents.last ?? ""
    }

    private static let swiftFunctionRegex = try! NSRegularExpression(pattern: #"(\w+)\.(\w+)"#, options: .anchorsMatchLines)
    private static let objcFunctionRegex = try! NSRegularExpression(pattern: #"-\[(\w+) (\w+)\]"#, options: .anchorsMatchLines)
    private static let pathRegex = try! NSRegularExpression(pattern: #"(\/.*?\.\S*):(\d*)"#, options: .anchorsMatchLines)

    static func functionsInModule(_ module: String) -> FunctionMap {
        var functionMap = FunctionMap()
        guard let symbolsInfo = DDSymbolicator.symbolsInfo(forLibrary: module) else {
            return functionMap
        }

        var currentFunctionName: String?
        symbolsInfo.components(separatedBy: .newlines).lazy.forEach { line in

            if line.contains("[FUNC, EXT, LENGTH") {
                // Swift exported functions
                if let match = swiftFunctionRegex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) {
                    guard let classNameRange = Range(match.range(at: 1), in: line),
                          let functionRange = Range(match.range(at: 2), in: line)

                    else {
                        return
                    }
                    currentFunctionName = String(line[classNameRange]) + "." + String(line[functionRange])
                }
            } else if line.contains("[FUNC, OBJC, LENGTH") {
                // ObjC exported functions
                if let match = objcFunctionRegex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) {
                    guard let classNameRange = Range(match.range(at: 1), in: line),
                          let functionRange = Range(match.range(at: 2), in: line)

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
                        } else {
                            functionMap[functionName] = FunctionInfo(file: file, startLine: line, endLine: line)
                        }
                    }
                }
            }
        }
        return functionMap
    }
}
