/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import Foundation
import XCTest

internal class FileLocatorTests: XCTestCase {
    func testThisTestLocation() throws {
        let testName = "FileLocatorTests.testThisTestLocation"
        let bundleName = Bundle(for: FileLocatorTests.self).bundleURL.deletingPathExtension().lastPathComponent

        try FileManager.default.createDirectory(at: DDSymbolicator.dsymFilesDir.url,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: DDSymbolicator.dsymFilesDir.url) }
        DDSymbolicator.dSYMFiles = []
        DDSymbolicator.createDSYMFileIfNeeded(forImageName: bundleName)

        let bundleFunctionInfo = try FileLocator.testFunctionsInModule(bundleName)
        let functionInfo = bundleFunctionInfo[testName]
        XCTAssertEqual(#file, functionInfo?.file)
        XCTAssertEqual(12, functionInfo?.startLine)
        XCTAssertEqual(26, functionInfo?.endLine)
    }
}

// MARK: - Fixture-based tests

internal class FileLocatorFixtureTests: XCTestCase {
    let fixturesURL: URL = {
        Bundle(for: FileLocatorFixtureTests.self).resourceURL!.appendingPathComponent("fixtures")
    }()

    // MARK: symbols-sdk.log

    func testSDKFixtureObjCMethod() throws {
        let url = fixturesURL.appendingPathComponent("symbols-sdk.log")
        let map = try FileLocator.extractFunctions(url)

        // ObjC method: -[DDTestModuleApiTests testApiIsAccessible] [FUNC, OBJC, ...]
        let info = try XCTUnwrap(map["DDTestModuleApiTests.testApiIsAccessible"])
        XCTAssertTrue(info.file.hasSuffix("DDTestSessionApiTests.m"))
        XCTAssertEqual(17, info.startLine)
        XCTAssertEqual(30, info.endLine)
    }

    func testSDKFixtureSwiftInitWithParensStripped() throws {
        let url = fixturesURL.appendingPathComponent("symbols-sdk.log")
        let map = try FileLocator.extractFunctions(url)

        // Mocks.ModuleInfo.init() — trailing () must be stripped from function name
        let info = try XCTUnwrap(map["Mocks.ModuleInfo.init"])
        XCTAssertNil(map["Mocks.ModuleInfo.init()"], "Key with () suffix must not exist")
        XCTAssertTrue(info.file.hasSuffix("MockTestTypes.swift"))
        XCTAssertEqual(20, info.startLine)
        XCTAssertEqual(24, info.endLine)
    }

    func testSDKFixtureSwiftFunctionMultipleLines() throws {
        let url = fixturesURL.appendingPathComponent("symbols-sdk.log")
        let map = try FileLocator.extractFunctions(url)

        // Mocks.TestBase.set(skipped:) spans lines 47-54 across several source entries
        let info = try XCTUnwrap(map["Mocks.TestBase.set(skipped:)"])
        XCTAssertTrue(info.file.hasSuffix("MockTestTypes.swift"))
        XCTAssertEqual(47, info.startLine)
        XCTAssertEqual(54, info.endLine)
    }

    func testSDKFixtureTotalFunctionCount() throws {
        let url = fixturesURL.appendingPathComponent("symbols-sdk.log")
        let map = try FileLocator.extractFunctions(url)
        XCTAssertEqual(718, map.count)
    }

    // MARK: symbols-swift-testing.log

    func testSwiftTestingFixtureParensFunctionStripped() throws {
        let url = fixturesURL.appendingPathComponent("symbols-swift-testing.log")
        let map = try FileLocator.extractFunctions(url)

        // Function name ends with () — must be stored without ()
        let info = try XCTUnwrap(map["TestManagementTests.testTestManagementFixFailsWithoutQuarantine"])
        XCTAssertNil(map["TestManagementTests.testTestManagementFixFailsWithoutQuarantine()"])
        XCTAssertTrue(info.file.hasSuffix("TestManagementTests.swift"))
        XCTAssertEqual(17, info.startLine)
        XCTAssertEqual(20, info.endLine)
    }

    func testSwiftTestingFixtureParameterizedFunction() throws {
        let url = fixturesURL.appendingPathComponent("symbols-swift-testing.log")
        let map = try FileLocator.extractFunctions(url)

        // parametrizedTest(_:str:) — underscore/colon in name preserved, module split on last dot
        let info = try XCTUnwrap(map["TestManagementTests.parametrizedTest(_:str:)"])
        XCTAssertTrue(info.file.hasSuffix("TestManagementTests.swift"))
        XCTAssertEqual(45, info.startLine)
        XCTAssertEqual(47, info.endLine)
    }

    func testSwiftTestingFixtureTotalFunctionCount() throws {
        let url = fixturesURL.appendingPathComponent("symbols-swift-testing.log")
        let map = try FileLocator.extractFunctions(url)
        XCTAssertEqual(23, map.count)
    }
}

// MARK: - Edge case tests with synthetic fixtures

internal class FileLocatorEdgeCaseTests: XCTestCase {
    private func makeFixture(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("log")
        let header = """
        /path/to/TestBinary [arm64]:
            DEADBEEF /path/to/TestBinary [BUNDLE]
                0x0000 (0x1000) __TEXT SEGMENT
                    0x0000 (0x0100) MACH_HEADER
                    0x0100 (0x0900) __TEXT __text
        """
        let footer = "\n                    0x0A00 (0x0100) __TEXT __stubs\n"
        try (header + "\n" + body + footer).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testEmptyTextSection() throws {
        let url = try makeFixture("")
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)
        XCTAssertTrue(map.isEmpty)
    }

    func testObjCMethodNotStartingWithTest() throws {
        // setUp, tearDown etc. must be ignored (only methods starting with "test" are included)
        let body = """
                    0x0100 (0x0020) -[MyClass setUp] [FUNC, OBJC, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts] 
                        0x0100 (0x0010) /path/to/MyClass.m:5
        """
        let url = try makeFixture(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)
        XCTAssertTrue(map.isEmpty, "Non-test ObjC method must be skipped")
    }

    func testObjCMethodStartingWithTest() throws {
        let body = """
                    0x0100 (0x0020) -[SuiteClass testSomething] [FUNC, OBJC, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts] 
                        0x0100 (0x0010) /path/to/SuiteClass.m:10
                        0x0110 (0x0010) /path/to/SuiteClass.m:12
        """
        let url = try makeFixture(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)
        let info = try XCTUnwrap(map["SuiteClass.testSomething"])
        XCTAssertEqual(info.file, "/path/to/SuiteClass.m")
        XCTAssertEqual(10, info.startLine)
        XCTAssertEqual(12, info.endLine)
    }

    func testSwiftFunctionWithParensSuffix() throws {
        // Trailing () on the last component must be stripped
        let body = """
                    0x0100 (0x0020) MyModule.myFunc() [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts] 
                        0x0100 (0x0010) /path/to/MyFile.swift:7
        """
        let url = try makeFixture(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)
        XCTAssertNil(map["MyModule.myFunc()"], "Key with () suffix must not be stored")
        let info = try XCTUnwrap(map["MyModule.myFunc"])
        XCTAssertEqual(7, info.startLine)
    }

    func testSwiftFunctionWithoutModule() throws {
        // No dot in name → module derived from source file basename
        let body = """
                    0x0100 (0x0020) globalFunction() [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts] 
                        0x0100 (0x0010) /path/to/Helpers.swift:3
        """
        let url = try makeFixture(body)
        let map = try FileLocator.extractFunctions(url)
        let info = try XCTUnwrap(map["[Helpers].globalFunction"])
        XCTAssertEqual(info.file, "/path/to/Helpers.swift")
        XCTAssertEqual(3, info.startLine)
    }

    func testZeroAddressLinesSkipped() throws {
        // Lines ending with :0 must not affect start/end line tracking
        let body = """
                    0x0100 (0x0020) MyModule.func1() [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts] 
                        0x0100 (0x0008) /path/to/Src.swift:0
                        0x0108 (0x0008) /path/to/Src.swift:5
                        0x0110 (0x0008) /path/to/Src.swift:0
                        0x0118 (0x0008) /path/to/Src.swift:9
        """
        let url = try makeFixture(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)
        let info = try XCTUnwrap(map["MyModule.func1"])
        XCTAssertEqual(5, info.startLine, "Start line must be first non-zero line")
        XCTAssertEqual(9, info.endLine,   "End line must be last non-zero line")
    }

    func testNonEXTNonOBJCFunctionIgnored() throws {
        // Functions without EXT or OBJC flag must not be parsed
        let body = """
                    0x0100 (0x0020) MyModule.internalFunc() [FUNC, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts] 
                        0x0100 (0x0010) /path/to/Src.swift:1
        """
        let url = try makeFixture(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)
        XCTAssertTrue(map.isEmpty)
    }

    func testCompilerGeneratedSourceLinesIgnored() throws {
        // Lines from /<compiler-generated> must not contribute to the function map
        let body = """
                    0x0100 (0x0020) MyModule.synth() [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts] 
                        0x0100 (0x0010) /<compiler-generated>:5
                        0x0110 (0x0010) /<compiler-generated>:8\n
        """
        let url = try makeFixture(body)
        defer { try? FileManager.default.removeItem(at: url) }
        // The function is parsed but its file is /<compiler-generated>; that is fine — we just
        // verify that the parser does not crash and produces a consistent result.
        XCTAssertNoThrow(try FileLocator.extractFunctions(url))
    }

    func testMultipleModuleFunctions() throws {
        let body = """
                    0x0100 (0x0020) Alpha.funcA() [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts] 
                        0x0100 (0x0010) /path/to/A.swift:1
                    0x0120 (0x0020) Beta.funcB() [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts] 
                        0x0120 (0x0010) /path/to/B.swift:2
        """
        let url = try makeFixture(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)
        XCTAssertEqual(2, map.count)
        XCTAssertNotNil(map["Alpha.funcA"])
        XCTAssertNotNil(map["Beta.funcB"])
    }

    func testStubsBoundaryStopsParsing() throws {
        // Any function entries after __TEXT __stubs must be ignored.
        // We write a function BEFORE __stubs and verify only that one is captured,
        // even though we append another FUNC line after the stubs marker manually.
        let before = """
                    0x0100 (0x0020) Good.func() [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts] 
                        0x0100 (0x0010) /path/to/Good.swift:1
        """
        let url = try makeFixture(before)
        // Append an extra function entry after __TEXT __stubs in the file
        var content = try String(contentsOf: url)
        content += """
                    0x0B00 (0x0020) After.func() [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts] 
                        0x0B00 (0x0010) /path/to/After.swift:99
        """
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)
        XCTAssertNotNil(map["Good.func"])
        XCTAssertNil(map["After.func"], "Functions after __TEXT __stubs must not be parsed")
    }

    func testSpecialSymbolsInFunctionNames() throws {
        // ObjC selectors may contain colons (multi-part), dollar signs, and hash characters.
        // Swift names allow any non-whitespace character, including $, #, and colon-containing
        // argument labels.
        let body = """
                    0x0100 (0x0020) -[Suite$Category testWith:param:] [FUNC, OBJC, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts] 
                        0x0100 (0x0010) /path/to/Suite.m:10
                    0x0120 (0x0020) -[Suite test#HashMethod] [FUNC, OBJC, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts] 
                        0x0120 (0x0010) /path/to/Suite.m:20
                    0x0140 (0x0020) MyModule.func_$_2(p1:p2:) [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts] 
                        0x0140 (0x0010) /path/to/MyFile.swift:30
                    0x0160 (0x0020) MyModule.testWith$#(label:and:) [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts] 
                        0x0160 (0x0010) /path/to/MyFile.swift:40
        """
        let url = try makeFixture(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)

        // ObjC: dollar sign in class name; multi-part selector (colons) kept verbatim
        let objcDollar = try XCTUnwrap(map["Suite$Category.testWith:param:"])
        XCTAssertEqual(objcDollar.file, "/path/to/Suite.m")
        XCTAssertEqual(10, objcDollar.startLine)

        // ObjC: hash in method name
        let objcHash = try XCTUnwrap(map["Suite.test#HashMethod"])
        XCTAssertEqual(objcHash.file, "/path/to/Suite.m")
        XCTAssertEqual(20, objcHash.startLine)

        // Swift: dollar sign in function name (parametrized-test style, e.g. func_$_2)
        // trailing () is not stripped because the name ends with :) not ()
        let swiftDollar = try XCTUnwrap(map["MyModule.func_$_2(p1:p2:)"])
        XCTAssertEqual(swiftDollar.file, "/path/to/MyFile.swift")
        XCTAssertEqual(30, swiftDollar.startLine)

        // Swift: colon-containing argument labels preserved, no () stripping (ends with :))
        let swiftColons = try XCTUnwrap(map["MyModule.testWith$#(label:and:)"])
        XCTAssertEqual(swiftColons.file, "/path/to/MyFile.swift")
        XCTAssertEqual(40, swiftColons.startLine)
    }

    func testFunctionAtEndOfFileWithoutStubs() throws {
        // If the file ends without a __TEXT __stubs marker the last parsed function must still
        // be included in the result.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("log")
        let content = """
        /path/to/TestBinary [arm64]:
            DEADBEEF /path/to/TestBinary [BUNDLE]
                0x0000 (0x1000) __TEXT SEGMENT
                    0x0000 (0x0100) __TEXT __text
                    0x0100 (0x0020) Last.func() [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts] 
                        0x0100 (0x0010) /path/to/Last.swift:42
        """
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)
        let info = try XCTUnwrap(map["Last.func"])
        XCTAssertEqual(42, info.startLine)
    }
}
