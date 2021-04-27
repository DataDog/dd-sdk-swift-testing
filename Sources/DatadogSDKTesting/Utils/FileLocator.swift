/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

struct FileLocator {
    /// It returns the file path and line of a test given the test class and test name
    static func filePath(forTestClass testClass: UnsafePointer<Int8>, testName: String, library: String) -> String {
        guard let objcClass = objc_getClass(testClass) as? AnyClass else {
            return ""
        }

        var testThrowsError = false
        var method = class_getInstanceMethod(objcClass, Selector(testName))
        if method == nil {
            //Try if the test throws an error
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
}
