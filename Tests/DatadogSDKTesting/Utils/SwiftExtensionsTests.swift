/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import XCTest
@testable import DatadogSDKTesting


internal class SwiftExtensionsTests: XCTestCase {

    func testAverageInEmptyArray_returnsZero() {
        let array:[Double] = []
        XCTAssertEqual(array.average, 0.0)
    }

    func testAverageArray_returnsCorrectValue() {
        let array = [1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0]
        XCTAssertEqual(array.average, 5.0)

    }
}
