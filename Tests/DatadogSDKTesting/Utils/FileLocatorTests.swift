/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import DatadogSDKTesting
import Foundation
import XCTest

internal class FileLocatorTests: XCTestCase {
    #if !os(tvOS)
        func testThisTestLocation() {
            let className = object_getClassName(self)
            let bundleName = Bundle(for: type(of: self)).bundleURL.deletingPathExtension().lastPathComponent

            let testNameRegex = try! NSRegularExpression(pattern: "([\\w]+) ([\\w]+)", options: .caseInsensitive)
            let namematch = testNameRegex.firstMatch(in: self.name, range: NSRange(location: 0, length: self.name.count))
            let nameRange = Range(namematch!.range(at: 2), in: self.name)
            let testName = String(self.name[nameRange!])

            let testSourcePath = FileLocator.filePath(forTestClass: className, testName: testName, library: bundleName)

            XCTAssertFalse(testSourcePath.isEmpty)
            let sourceComponents = testSourcePath.components(separatedBy: ":")
            XCTAssertEqual(#file, sourceComponents[0])
            XCTAssertEqual("13", sourceComponents[1])
        }
    #endif
}
