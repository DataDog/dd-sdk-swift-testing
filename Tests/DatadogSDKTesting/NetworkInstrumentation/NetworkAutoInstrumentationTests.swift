/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting
import OpenTelemetrySdk

private struct MockURLFilter: URLFiltering {
    let allow: Bool
    func allows(_ url: URL?) -> Bool {
        return allow
    }
}


class NetworkAutoInstrumentationTests: XCTestCase {
    func testInitialization() throws {
        let autoInstrumentation = NetworkAutoInstrumentation ( urlFilter: URLFilter(includedHosts: ["included.com"],
                                                                                    excludedURLs: ["excluded.com"])
        )

        let urlFilter = try XCTUnwrap(autoInstrumentation?.urlFilter as? URLFilter)
        let expectedURLFilter = URLFilter(
            includedHosts: ["included.com"],
            excludedURLs: ["excluded.com"]
        )

        XCTAssertEqual(urlFilter, expectedURLFilter)
    }
}
