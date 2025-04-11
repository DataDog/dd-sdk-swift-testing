//
//  KnownTestsTests.swift
//  DatadogSDKTestingTests
//
//  Created by Yehor Popovych on 26/03/2025.
//

import XCTest
@testable import DatadogSDKTesting

final class KnownTestsTests: XCTestCase {
    func testKnownTestIsMarked() {
        let module = "SomeModule"
        let knownSuite = "KnownSuite"
        let knownSuiteKnownTest = "testKnownSuiteKnownTest"
        let knownSuiteUnknownTest = "testKnownSuiteUnknownTest"
        
        let unknownSuite = "UnknwownSuite"
        let unknownSuiteUnknownTest = "testUnknownSuiteUnknownTest"
        
        let knownTestsMap = [module: [knownSuite: [knownSuiteKnownTest]]]
        
        let feature: TestHooksFeature = KnownTests(tests: knownTestsMap)
        
        DDTestModule(bundleName: <#T##String#>, startTime: <#T##Date?#>)
        
        feature.testSuiteWillStart(suite: <#T##DDTestSuite#>, testsCount: <#T##UInt#>)
        
    }
}

extension KnownTestsTests {
    final class NamedTest: XCTestCase {
        private var _method: String!
        private var _suite: String!
        
        override var name: String { "-[\(_suite!) \(_method!)]" }
        
        func _emptyMethod() {}
        
        static func suite(named name: String, methods: [String]) -> XCTestSuite {
            let suite = XCTestSuite(name: name)
            for method in methods {
                let test = Self(selector: #selector(_emptyMethod))
                test._method = method
                test._suite = name
                suite.addTest(test)
            }
            return suite
        }
    }
}
