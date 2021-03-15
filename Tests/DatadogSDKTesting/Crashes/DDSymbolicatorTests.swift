/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import DatadogSDKTesting
import XCTest

class DDSymbolicatorTests: XCTestCase {
    func testGenerateSwiftName1() throws {
        let className = "Module.Class"
        let functionName = "testName"
        let throwsError = false
        let desiredResult = "_$s6Module5ClassC8testNameyyF"

        let mangledName = DDSymbolicator.swiftTestMangledName(forClassName: className, testName: functionName, throwsError: throwsError)
        XCTAssertEqual(desiredResult, mangledName)
    }

    func testGenerateSwiftName2() throws {
        let className = "DemoSwiftTests.DemoSwiftTests"
        let functionName = "testExampleSuccess"
        let throwsError = true
        let desiredResult = "_$s14DemoSwiftTestsAAC18testExampleSuccessyyKF"

        let mangledName = DDSymbolicator.swiftTestMangledName(forClassName: className, testName: functionName, throwsError: throwsError)
        XCTAssertEqual(desiredResult, mangledName)
    }

    func testGenerateSwiftName3() throws {
        let className = "DatadogTests.SyntheticTestUniversalLink_Tests"
        let functionName = "testParseInvalidURL"
        let throwsError = false
        let desiredResult = "_$s12DatadogTests027SyntheticTestUniversalLink_B0C19testParseInvalidURLyyF"

        let mangledName = DDSymbolicator.swiftTestMangledName(forClassName: className, testName: functionName, throwsError: throwsError)
        XCTAssertEqual(desiredResult, mangledName)
    }

    func testGenerateSwiftName4() throws {
        let className = "DatadogTests.ActiveSpansPoolTests"
        let functionName = "testsWhenSpanIsStartedIsAssignedToActiveSpan"
        let throwsError = true
        let desiredResult = "_$s12DatadogTests015ActiveSpansPoolB0C022testsWhenSpanIsStartedi10AssignedTocH0yyKF"

        let mangledName = DDSymbolicator.swiftTestMangledName(forClassName: className, testName: functionName, throwsError: throwsError)
        XCTAssertEqual(desiredResult, mangledName)
    }

    func testGenerateSwiftName5() throws {
        let className = "DatadogTests.TimeframeFormatter_Tests"
        let functionName = "testSimpleToday"
        let throwsError = true
        let desiredResult = "_$s12DatadogTests019TimeframeFormatter_B0C15testSimpleTodayyyKF"

        let mangledName = DDSymbolicator.swiftTestMangledName(forClassName: className, testName: functionName, throwsError: throwsError)
        XCTAssertEqual(desiredResult, mangledName)
    }

    func testGenerateSwiftName6() throws {
        let className = "DatadogTests.LocalizedStrings_Tests"
        let functionName = "testPluralStrings"
        let throwsError = false
        let desiredResult = "_$s12DatadogTests017LocalizedStrings_B0C010testPluralD0yyF"

        let mangledName = DDSymbolicator.swiftTestMangledName(forClassName: className, testName: functionName, throwsError: throwsError)
        XCTAssertEqual(desiredResult, mangledName)
    }

    func testGenerateSwiftName7() throws {
        let className = "DemoSwiftTests.DemoSwiftyTests"
        let functionName = "testExampleSuccessExampleSuccess"
        let throwsError = true
        let desiredResult = "_$s14DemoSwiftTests0a6SwiftyC0C018testExampleSuccessfG0yyKF"

        let mangledName = DDSymbolicator.swiftTestMangledName(forClassName: className, testName: functionName, throwsError: throwsError)
        XCTAssertEqual(desiredResult, mangledName)
    }

    func testGenerateSwiftName8() throws {
        let className = "DemoSwiftSwiftTests.DemoSwiftyTests"
        let functionName = "testExampleSuccessExampleSuccess"
        let throwsError = true
        let desiredResult = "_$s09DemoSwiftB5Tests0a6SwiftyC0C018testExampleSuccessfG0yyKF"

        let mangledName = DDSymbolicator.swiftTestMangledName(forClassName: className, testName: functionName, throwsError: throwsError)
        XCTAssertEqual(desiredResult, mangledName)
    }

    func testGenerateSwiftName9() throws {
        let className = "DemoSwiftTests.DemoSwiftyTests"
        let functionName = "testExamplesSuccessExExaExamExampExamplExamplesexamples"
        let throwsError = true
        let desiredResult = "_$s14DemoSwiftTests0a6SwiftyC0C55testExamplesSuccessExExaExamExampExamplExamplesexamplesyyKF"

        let mangledName = DDSymbolicator.swiftTestMangledName(forClassName: className, testName: functionName, throwsError: throwsError)
        XCTAssertEqual(desiredResult, mangledName)
    }

    func testGenerateSwiftName10() throws {
        let className = "DemoSwiftTests.Class"
        let functionName = "testName"
        let throwsError = false
        let desiredResult = "_$s14DemoSwiftTests5ClassC8testNameyyF"

        let mangledName = DDSymbolicator.swiftTestMangledName(forClassName: className, testName: functionName, throwsError: throwsError)
        XCTAssertEqual(desiredResult, mangledName)
    }

    func testGenerateSwiftName11() throws {
        let className = "DemoSwiftTests.Class"
        let functionName = "testName_name_name_Name"
        let throwsError = false
        let desiredResult = "_$s14DemoSwiftTests5ClassC014testName_name_g1_F0yyF"

        let mangledName = DDSymbolicator.swiftTestMangledName(forClassName: className, testName: functionName, throwsError: throwsError)
        XCTAssertEqual(desiredResult, mangledName)
    }

    func testGenerateSwiftName12() throws {
        let className = "DemoSwiftTests.Class"
        let functionName = "testDemoSwiftTests"
        let throwsError = false
        let desiredResult = "_$s14DemoSwiftTests5ClassC04testabC0yyF"

        let mangledName = DDSymbolicator.swiftTestMangledName(forClassName: className, testName: functionName, throwsError: throwsError)
        XCTAssertEqual(desiredResult, mangledName)
    }

    func testGenerateSwiftName13() throws {
        let className = "DemoSwiftTests.Class"
        let functionName = "testDemoSwiftTestsClass"
        let throwsError = false
        let desiredResult = "_$s14DemoSwiftTests5ClassC04testabcD0yyF"

        let mangledName = DDSymbolicator.swiftTestMangledName(forClassName: className, testName: functionName, throwsError: throwsError)
        XCTAssertEqual(desiredResult, mangledName)
    }

    func testGenerateSwiftName14() throws {
        let className = "DemoSwiftTests.Class"
        let functionName = "testDemoSwiftClassTestsClass"
        let throwsError = false
        let desiredResult = "_$s14DemoSwiftTests5ClassC04testabdcD0yyF"

        let mangledName = DDSymbolicator.swiftTestMangledName(forClassName: className, testName: functionName, throwsError: throwsError)
        XCTAssertEqual(desiredResult, mangledName)
    }

    func testGenerateSwiftName15() throws {
        let className = "DatadogTests.ForcedUpdateViewModel_Tests"
        let functionName = "testAppStoreURL_appStore_https"
        let throwsError = true
        let desiredResult = "_$s12DatadogTests022ForcedUpdateViewModel_B0C019testAppStoreURL_appI6_httpsyyKF"

        let mangledName = DDSymbolicator.swiftTestMangledName(forClassName: className, testName: functionName, throwsError: throwsError)
        XCTAssertEqual(desiredResult, mangledName)
    }

    func testGenerateSwiftName16() throws {
        let className = "DogAPITests.APITests"
        let functionName = "testDecode"
        let throwsError = true
        let desiredResult = "_$s11DogAPITests0B0C10testDecodeyyKF"

        let mangledName = DDSymbolicator.swiftTestMangledName(forClassName: className, testName: functionName, throwsError: throwsError)
        XCTAssertEqual(desiredResult, mangledName)
    }

    func testGenerateSwiftName17() throws {
        let className = "DogKitTests.DispatchTimeIntervalShortcutsTests"
        let functionName = "testTimeInterval_Fallback"
        let throwsError = false
        let desiredResult = "_$s11DogKitTests029DispatchTimeIntervalShortcutsC0C04testeF9_FallbackyyF"

        let mangledName = DDSymbolicator.swiftTestMangledName(forClassName: className, testName: functionName, throwsError: throwsError)
        XCTAssertEqual(desiredResult, mangledName)
    }
}
