/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting

final class KnownTestsLogicTests: XCTestCase {
    func testUnknownTestIsMarkedProperly() {
        let module = "SomeModule"
        let knownSuite = "KnownSuite"
        let knownSuiteKnownTest = "testKnownSuiteKnownTest"
        let knownSuiteUnknownTest = "testKnownSuiteUnknownTest"
        
        let unknownSuite = "UnknwownSuite"
        let unknownSuiteUnknownTest = "testUnknownSuiteUnknownTest"
        
        let knownTestsMap = [module: [knownSuite: [knownSuiteKnownTest]]]
        
        let feature: TestHooksFeature = KnownTests(tests: knownTestsMap)
        
        let testsToRun: Mocks.Runner.Tests = [module: [
            knownSuite: [
                knownSuiteKnownTest: .pass(),
                knownSuiteUnknownTest: .pass()
            ],
            unknownSuite: [unknownSuiteUnknownTest: .fail("SomeERROR")]
        ]]
        
        let results = Mocks.Runner(features: [feature], tests: testsToRun).run()
        
        let knownSuiteResult = results[module]![knownSuite]!
        let unknownSuiteResult = results[module]![unknownSuite]!
        
        XCTAssertNotNil(knownSuiteResult[knownSuiteKnownTest]?[0])
        XCTAssertNil(knownSuiteResult[knownSuiteKnownTest]?[0]?.tags[DDTestTags.testIsNew])
        
        XCTAssertEqual(knownSuiteResult[knownSuiteUnknownTest]?[0]?.tags[DDTestTags.testIsNew], "true")
        
        XCTAssertEqual(unknownSuiteResult[unknownSuiteUnknownTest]?[0]?.tags[DDTestTags.testIsNew], "true")
    }
}
