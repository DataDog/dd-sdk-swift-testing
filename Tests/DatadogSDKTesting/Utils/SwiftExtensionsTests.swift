/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import Foundation
import XCTest

internal class SwiftExtensionsTests: XCTestCase {
    func testAverageInEmptyArray_returnsZero() {
        let array: [Double] = []
        XCTAssertEqual(array.average, 0.0)
    }

    func testAverageArray_returnsCorrectValue() {
        let array = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]
        XCTAssertEqual(array.average, 5.0)
    }

    func testCamelCase_returns_correctly1() {
        let string = "TestNameStandard"
        XCTAssertEqual(string.separatedByWords, "Test Name Standard")
    }

    func testCamelCase_returns_correctly2() {
        let string = "TestNAmeStandard"
        XCTAssertEqual(string.separatedByWords, "Test NAme Standard")
    }

    func testCamelCase_returns_correctly3() {
        let string = "TestNAMStandard"
        XCTAssertEqual(string.separatedByWords, "Test NAMStandard")
    }

    func testCamelCase_returns_correctly4() {
        let string = "testNameStandard"
        XCTAssertEqual(string.separatedByWords, "test Name Standard")
    }

    func testCamelCase_returns_correctly5() {
        let string = "TestNameStandardD"
        XCTAssertEqual(string.separatedByWords, "Test Name StandardD")
    }

    func testCamelCase_returns_correctly6() {
        let string = "Test_NAMStandard"
        XCTAssertEqual(string.separatedByWords, "Test_ NAMStandard")
    }

    func testCamelCase_returns_correctly7() {
        let string = "te_stNameSt__andard"
        XCTAssertEqual(string.separatedByWords, "te_ st Name St_ _ andard")
    }

    func testCamelCase_returns_correctly8() {
        let string = "TestNameS_tandardD"
        XCTAssertEqual(string.separatedByWords, "Test NameS_ tandardD")
    }

    func testCamelCase_returns_correctly9() {
        let string = "testAppStoreURL_appStore_https"
        XCTAssertEqual(string.separatedByWords, "test App Store URL_ app Store_ https")
    }

    func testCamelCase_returns_correctly10() {
        let string = "APITests"
        XCTAssertEqual(string.separatedByWords, "APITests")
    }
}

class DataExtensionsTests: XCTestCase {
    func testHexStringToDataGood() {
        let data1 = Data(hex: "0x0123456789abcdef")
        let data2 = Data(hex: "0123456789ABCDEF")
        XCTAssertNotNil(data1)
        XCTAssertNotNil(data2)
        XCTAssertEqual(data1, data2)
        XCTAssertEqual(data1, Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]))
    }
    
    func testHexStringToDataBad() {
        let data1 = Data(hex: "0123456789abcde")
        let data2 = Data(hex: "0123456789ABCDEFGH")
        XCTAssertNil(data1)
        XCTAssertNil(data2)
    }
    
    func testDataToHexString() {
        XCTAssertEqual(Data(repeating: 0x00, count: 5).hex(prefix: false), Array(repeating: "00", count: 5).joined())
        XCTAssertEqual(Data(repeating: 0x00, count: 5).hex(prefix: true), "0x" + Array(repeating: "00", count: 5).joined())
        XCTAssertEqual(Data(repeating: 0xff, count: 5).hex(prefix: false), Array(repeating: "ff", count: 5).joined())
        XCTAssertEqual(Data(repeating: 0x10, count: 5).hex(prefix: false), Array(repeating: "10", count: 5).joined())
        XCTAssertEqual(Data(repeating: 0xf0, count: 5).hex(prefix: false), Array(repeating: "f0", count: 5).joined())
    }
    
}
