/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
import XCTest
@testable import DatadogSDKTesting

internal class DDErrorTests: XCTestCase {

    func testErrorCreatedWithSwiftError() {
        let internalError = InternalError(description: "desc")
        let ddError = DDError(error: internalError)

        XCTAssertEqual(ddError.title, "InternalError")
        XCTAssertEqual(ddError.message, "desc")
        XCTAssertEqual(ddError.details, "desc")
    }

    func testErrorCreatedWithNSError() {
        let nsError = NSError(domain: "domain", code: 3, userInfo: nil)
        let ddError = DDError(error: nsError)

        XCTAssertEqual(ddError.title, "domain - 3")
    }

}
