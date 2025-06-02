//
//  KnownTestsTests.swift
//  DatadogSDKTestingTests
//
//  Created by Yehor Popovych on 26/03/2025.
//

import XCTest
@testable import DatadogSDKTesting

final class KnownTestsTests: XCTestCase {
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
                knownSuiteKnownTest: [.pass()],
                knownSuiteUnknownTest: [.pass()]
            ],
            unknownSuite: [unknownSuiteUnknownTest: [.fail(.init(type: "SomeERROR"))]]
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
