/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest

final class SwiftUtilsTests: XCTestCase {
    func testCStringArray() {
        let strings = ["aba", "abacaba", "abacabadaba", "", "test123", ""]
        strings.withCStringsArray { array in
            XCTAssertEqual(strings.count, array.count)
            zip(array, strings).forEach { (cstr, str) in
                XCTAssertEqual(strcmp(cstr, str), 0)
            }
        }
    }
}
