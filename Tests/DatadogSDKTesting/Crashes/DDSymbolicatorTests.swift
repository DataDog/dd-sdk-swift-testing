/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import XCTest

class DDSymbolicatorTests: XCTestCase {
    func testGetCallStack() {
        var callStack: [String] = [String]()
        measure {
             callStack = DDSymbolicator.getCallStack()
        }
        XCTAssert(callStack[0].hasPrefix("0\t"))
        XCTAssert(callStack[0].contains("DDSymbolicatorTests.testGetCallStack() -> ()"))
    }

//    func testGetCallStackSymbolicated() {
//        let bundleName = Bundle(for: DDSymbolicatorTests.self).bundleURL.deletingPathExtension().lastPathComponent
//        DDSymbolicator.createDSYMFileIfNeeded(forImageName: bundleName)
//
//        let callStack = DDSymbolicator.getCallStackSymbolicated()
//#if os(tvOS)
//        XCTAssert(callStack[0].hasPrefix("0 "))
//        XCTAssert(callStack[0].contains("DDSymbolicatorTests.testGetCallStackSymbolicated() -> ()"))
//#else
//        XCTAssert(callStack[0].hasPrefix("0 "))
//        XCTAssert(callStack[0].contains("DDSymbolicatorTests.testGetCallStackSymbolicated()"))
//#if os(macOS)
//        XCTAssert(callStack[0].contains("(in DatadogSDKTestingTests_macOS)"))
//#else
//        XCTAssert(callStack[0].contains("(in DatadogSDKTestingTests_iOS)"))
//#endif
//        XCTAssert(callStack[0].contains("DDSymbolicatorTests.swift:21"))
//
//#endif
//    }
}
