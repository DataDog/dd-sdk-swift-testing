/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import IntegrationTests
import XCTest

class UIIntegrationTests: XCTestCase {
    var testOutputFile: URL!

    override func setUpWithError() throws {
        guard let namematch = IntegrationTestsRunner.testNameRegex.firstMatch(in: self.name, range: NSRange(location: 0, length: self.name.count)),
              let nameRange = Range(namematch.range(at: 2), in: self.name)
        else {
            return
        }
        let testName = String(self.name[nameRange])
        testOutputFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(testName).appendingPathExtension("json")
    }

    func testUIIntegrationNetwork() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TEST_OUTPUT_FILE"] = testOutputFile.path
        app.launch()

        guard let returnSpans = getTestResult() else {
            XCTFail("No spans sent")
            return
        }
        let recoveredSpans = try XCTUnwrap(returnSpans)
        let networkSpan = recoveredSpans.first

        XCTAssertNotNil(networkSpan)
        XCTAssertEqual(networkSpan?.stringAttributes["http.method"], "GET")
    }

    func getTestResult() -> [SimpleSpanData]? {
        guard let outputFile = FileHandle(forReadingAtPath: testOutputFile.path) else {
            XCTFail("internal test didn export file")
            return nil
        }
        let resultSpans = try? JSONDecoder().decode([SimpleSpanData].self, from: outputFile.availableData)
        return resultSpans
    }
}
