/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import Foundation
import XCTest

internal class FileLocatorTests: XCTestCase {
    func testThisTestLocation() {
        let testName = "FileLocatorTests.testThisTestLocation"
        let bundleName = Bundle(for: FileLocatorTests.self).bundleURL.deletingPathExtension().lastPathComponent
        DDSymbolicator.createDSYMFileIfNeeded(forImageName: bundleName)

        let bundleFunctionInfo = FileLocator.testFunctionsInModule(bundleName)
        let functionInfo = bundleFunctionInfo[testName]
        XCTAssertEqual(#file, functionInfo?.file)
        XCTAssertEqual(12, functionInfo?.startLine)
        XCTAssertEqual(22, functionInfo?.endLine)
    }
}
