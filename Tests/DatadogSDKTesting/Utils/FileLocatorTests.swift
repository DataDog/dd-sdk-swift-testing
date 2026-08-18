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
        XCTAssertEqual(27, functionInfo?.endLine)
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

    // MARK: symbols-async-thunk.log (SDTEST-3944 regression)

    // Captured from a real `-O` build of an XCTestCase with sync/async/throwing test
    // methods (`symbols -fullSourcePath -lazy` output). Under optimization, an async test
    // method's own EXT-tagged DWARF entry can carry only `/<compiler-generated>:0` lines
    // (no source info) — the real body lives in a `specialized` clone, which is untagged,
    // named differently (`specialized Module.func()`), and lands far from the original
    // entry with unrelated functions interleaved. Before the SDTEST-3944 fix this caused
    // the async test methods to be dropped from the map entirely (`test.source.file` missing).

    func testAsyncThunkFixtureRecoversAllAsyncTestMethods() throws {
        let url = fixturesURL.appendingPathComponent("symbols-async-thunk.log")
        let map = try FileLocator.extractFunctions(url)

        let throwsInfo = try XCTUnwrap(map["AsyncRepro.testAsyncThrows"])
        XCTAssertTrue(throwsInfo.file.hasSuffix("AsyncTests.swift"))
        XCTAssertEqual(11, throwsInfo.startLine)
        XCTAssertEqual(19, throwsInfo.endLine)

        let plainInfo = try XCTUnwrap(map["AsyncRepro.testAsyncPlain"])
        XCTAssertEqual(21, plainInfo.startLine)
        XCTAssertEqual(28, plainInfo.endLine)

        let manyAwaitsInfo = try XCTUnwrap(map["AsyncRepro.testAsyncManyAwaits"])
        XCTAssertEqual(30, manyAwaitsInfo.startLine)
        XCTAssertEqual(36, manyAwaitsInfo.endLine)

        // The simple sync method in the same suite must still resolve as before.
        let syncInfo = try XCTUnwrap(map["AsyncRepro.testSync"])
        XCTAssertEqual(6, syncInfo.startLine)
        XCTAssertEqual(8, syncInfo.endLine)

        // A different suite's async method, whose first chunk already carries real lines,
        // must also still resolve.
        let otherInfo = try XCTUnwrap(map["AsyncRepro2.testOtherAsync"])
        XCTAssertEqual(40, otherInfo.startLine)
        XCTAssertEqual(43, otherInfo.endLine)
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

    func testSwiftBacktickQuotedNameWithSpaces() throws {
        // Swift Testing allows backtick-quoted function names containing spaces,
        // e.g. `func \`failing parameterized test\`(_ p1: SomeEnum)`. The name plus its
        // parameter list must be captured verbatim, not truncated at the first space.
        // (FUNC lines must end with a trailing space; `\(" ")` keeps it lint-proof.)
        let body = """
                    0x0100 (0x0020) TestModule.`failing parameterized test`(_:) [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts]\(" ")
                        0x0100 (0x0010) /path/to/Tests.swift:50
                        0x0110 (0x0010) /path/to/Tests.swift:53
        """
        let url = try makeFixture(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)
        let info = try XCTUnwrap(map["TestModule.`failing parameterized test`(_:)"])
        XCTAssertEqual(info.file, "/path/to/Tests.swift")
        XCTAssertEqual(50, info.startLine)
        XCTAssertEqual(53, info.endLine)
    }

    func testSwiftBacktickQuotedNameWithDotInside() throws {
        // A dot inside a backtick-quoted name must not be mistaken for the module separator.
        let body = """
                    0x0100 (0x0020) TestModule.`test 3.0 behavior`() [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts]\(" ")
                        0x0100 (0x0010) /path/to/Tests.swift:12
        """
        let url = try makeFixture(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)
        // trailing () stripped; module split before the backtick, not on the inner dot
        let info = try XCTUnwrap(map["TestModule.`test 3.0 behavior`"])
        XCTAssertEqual(info.file, "/path/to/Tests.swift")
        XCTAssertEqual(12, info.startLine)
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
    
    func testAllMethodHasIsClosure() throws {
        // for wrappers and etc. Test function will be split in two
        let body = """
                        0x0000000000002358 (   0x108) MyModule.myFunc() [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts] 
                            0x0000000000002358 (    0x34) /path/to/mymodule.swift:12
                            0x000000000000238c (     0xc) /path/to/mymodule.swift:12
                            0x0000000000002398 (    0x24) /path/to/mymodule.swift:13
                            0x00000000000023bc (    0x2c) /path/to/mymodule.swift:0
                            0x00000000000023e8 (    0x68) /path/to/mymodule.swift:13
                            0x0000000000002450 (    0x10) /path/to/mymodule.swift:13
                        0x0000000000002460 (    0xe4) MyModule.myFunc() [FUNC, LENGTH, NameNList, MangledNameNList, Merged, NList, DebugMap, FunctionStarts] 
                            0x0000000000002460 (    0x20) /path/to/mymodule.swift:13
                            0x0000000000002480 (    0x3c) /path/to/mymodule.swift:13
                            0x00000000000024bc (    0x20) /path/to/mymodule.swift:0
                            0x00000000000024dc (     0xc) /path/to/mymodule.swift:24
                            0x00000000000024e8 (    0x10) /path/to/mymodule.swift:24
                            0x00000000000024f8 (     0xc) /path/to/mymodule.swift:0
                            0x0000000000002504 (    0x28) /path/to/mymodule.swift:13
                            0x000000000000252c (     0x8) /path/to/mymodule.swift:23
                            0x0000000000002534 (    0x10) /path/to/mymodule.swift:23
        """
        let url = try makeFixture(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)
        let info = try XCTUnwrap(map["MyModule.myFunc"])
        XCTAssertEqual(12, info.startLine)
        XCTAssertEqual(24, info.endLine)
    }

    // MARK: SDTEST-3944 regression — async thunk source-line recovery

    func testAsyncFunctionSourceRecoveredFromNonAdjacentSpecializedClone() throws {
        // The EXT-tagged entry and its immediate `@objc` thunk carry no real source line
        // (compiler-generated bootstrap only). The real lines live in a `specialized` clone
        // that is untagged and separated from the original by an unrelated function — it
        // must still be matched back to the tracked function by name.
        let body = """
                    0x0100 (0x0020) AsyncSuite.testFoo() [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, Dwarf]\(" ")
                        0x0100 (0x0020) /<compiler-generated>:0
                    0x0120 (0x0020) @objc AsyncSuite.testFoo() [FUNC, LENGTH, NameNList, MangledNameNList, Merged, NList, Dwarf]\(" ")
                        0x0120 (0x0020) /<compiler-generated>:0
                    0x0140 (0x0020) Other.unrelated() [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, Dwarf]\(" ")
                        0x0140 (0x0010) /path/to/Other.swift:1
                    0x0160 (0x0020) specialized AsyncSuite.testFoo() [FUNC, LENGTH, NameNList, MangledNameNList, Merged, NList, Dwarf]\(" ")
                        0x0160 (0x0010) /path/to/AsyncSuite.swift:10
                        0x0170 (0x0010) /path/to/AsyncSuite.swift:12
        """
        let url = try makeFixture(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)

        let info = try XCTUnwrap(map["AsyncSuite.testFoo"])
        XCTAssertEqual(info.file, "/path/to/AsyncSuite.swift")
        XCTAssertEqual(10, info.startLine)
        XCTAssertEqual(12, info.endLine)
        XCTAssertNotNil(map["Other.unrelated"])
    }

    func testObjcThunkContinuationMergedIntoTrackedFunction() throws {
        // An immediately-adjacent `@objc` thunk that happens to carry real lines must be
        // merged into the tracked function's range (previously never matched because the
        // continuation regex could not span the space in "@objc Module.func()").
        let body = """
                    0x0100 (0x0020) AsyncSuite.testFoo() [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, Dwarf]\(" ")
                        0x0100 (0x0010) /path/to/AsyncSuite.swift:5
                    0x0120 (0x0020) @objc AsyncSuite.testFoo() [FUNC, LENGTH, NameNList, MangledNameNList, Merged, NList, Dwarf]\(" ")
                        0x0120 (0x0010) /path/to/AsyncSuite.swift:7
        """
        let url = try makeFixture(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)

        let info = try XCTUnwrap(map["AsyncSuite.testFoo"])
        XCTAssertEqual(5, info.startLine)
        XCTAssertEqual(7, info.endLine)
    }

    func testContinuationWithSyntheticSourcePathDoesNotEstablishLocation() throws {
        // When the declaration chunk has no usable source line, a continuation chunk may
        // establish the function's location — but only from real source. Compiler-generated
        // and macro-expansion buffers must not be reported as the test's file, otherwise
        // `test.source.file` points at a temporary buffer and codeowners resolution breaks.
        let body = """
                    0x0100 (0x0020) AsyncSuite.testFoo() [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, Dwarf]\(" ")
                        0x0100 (0x0020) /<compiler-generated>:0
                    0x0120 (0x0020) closure #2 in AsyncSuite.testFoo() [FUNC, LENGTH, NameNList, MangledNameNList, Merged, NList, Dwarf]\(" ")
                        0x0120 (0x0008) /var/folders/x/T/swift-generated-sources/@__swiftmacro_5Tests9testFooyyFMf_.swift:1
                        0x0128 (0x0008) /<compiler-generated>:7
                        0x0130 (0x0008) /path/to/AsyncSuite.swift:10
                        0x0138 (0x0008) /path/to/AsyncSuite.swift:14
        """
        let url = try makeFixture(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)

        let info = try XCTUnwrap(map["AsyncSuite.testFoo"])
        XCTAssertEqual(info.file, "/path/to/AsyncSuite.swift",
                       "Synthetic macro/compiler buffers must not become the test's source file")
        XCTAssertEqual(10, info.startLine)
        XCTAssertEqual(14, info.endLine)
    }

    func testUnicodeFunctionNames() throws {
        // Swift and ObjC identifiers may be non-ASCII, and Swift Testing names are arbitrary
        // text inside backticks. Names must survive verbatim, and a continuation chunk of a
        // non-ASCII function must still be matched back to it.
        let body = """
                    0x0100 (0x0020) MyTests.testПривет() [FUNC, EXT, LENGTH, NameNList, Merged, NList, Dwarf]\(" ")
                        0x0100 (0x0010) /путь/к/Файл.swift:10
                    0x0120 (0x0020) MyTests.测试方法() [FUNC, EXT, LENGTH, NameNList, Merged, NList, Dwarf]\(" ")
                        0x0120 (0x0010) /path/to/CJK.swift:20
                    0x0140 (0x0020) MyTests.`тест с пробелами`() [FUNC, EXT, LENGTH, NameNList, Merged, NList, Dwarf]\(" ")
                        0x0140 (0x0010) /path/to/Back.swift:30
                    0x0160 (0x0020) MyTests.test🎉Emoji() [FUNC, EXT, LENGTH, NameNList, Merged, NList, Dwarf]\(" ")
                        0x0160 (0x0010) /path/to/Emoji.swift:40
                    0x0180 (0x0020) -[ЮникодTests testМетод] [FUNC, OBJC, LENGTH, NameNList, Merged, NList, Dwarf]\(" ")
                        0x0180 (0x0010) /path/to/ObjC.m:50
                    0x01C0 (0x0020) specialized MyTests.testПривет() [FUNC, LENGTH, NameNList, Merged, NList, Dwarf]\(" ")
                        0x01C0 (0x0010) /путь/к/Файл.swift:14
        """
        let url = try makeFixture(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)

        let cyrillic = try XCTUnwrap(map["MyTests.testПривет"])
        XCTAssertEqual(cyrillic.file, "/путь/к/Файл.swift")
        XCTAssertEqual(10, cyrillic.startLine)
        XCTAssertEqual(14, cyrillic.endLine, "Continuation of a non-ASCII name must be merged")

        XCTAssertEqual(20, try XCTUnwrap(map["MyTests.测试方法"]).startLine)
        XCTAssertEqual(30, try XCTUnwrap(map["MyTests.`тест с пробелами`"]).startLine)
        XCTAssertEqual(40, try XCTUnwrap(map["MyTests.test🎉Emoji"]).startLine)
        // ObjC class/selector with Cyrillic letters — the `\w` class is Unicode-aware
        XCTAssertEqual(50, try XCTUnwrap(map["ЮникодTests.testМетод"]).startLine)
    }

    func testStartLineIsRunningMinimum() throws {
        // Chunks are not emitted in source order, so a later chunk may carry a lower line
        // than the one that opened the range.
        let body = """
                    0x0100 (0x0020) MyModule.myFunc() [FUNC, EXT, LENGTH, NameNList, Merged, NList, Dwarf]\(" ")
                        0x0100 (0x0010) /path/to/My.swift:20
                        0x0110 (0x0010) /path/to/My.swift:25
                    0x0120 (0x0020) specialized MyModule.myFunc() [FUNC, LENGTH, NameNList, Merged, NList, Dwarf]\(" ")
                        0x0120 (0x0010) /path/to/My.swift:18
                        0x0130 (0x0010) /path/to/My.swift:27
        """
        let url = try makeFixture(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)

        let info = try XCTUnwrap(map["MyModule.myFunc"])
        XCTAssertEqual(18, info.startLine, "startLine must fall to the lowest line seen")
        XCTAssertEqual(27, info.endLine)
    }

    func testSecondDeclarationOfSameNameReplacesRangeInsteadOfWidening() throws {
        // Generic functions can be emitted as several distinct EXT declarations at different
        // source lines. Each declaration must replace the recorded range rather than merge
        // with the previous one, which would report a span covering both bodies.
        let body = """
                    0x0100 (0x0020) MyModule.withTest<A>(named:_:) [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, Dwarf]\(" ")
                        0x0100 (0x0010) /path/to/My.swift:262
                        0x0110 (0x0010) /path/to/My.swift:263
                    0x0120 (0x0020) MyModule.withTest<A>(named:_:) [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, Dwarf]\(" ")
                        0x0120 (0x0010) /path/to/My.swift:266
                        0x0130 (0x0010) /path/to/My.swift:268
        """
        let url = try makeFixture(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)

        let info = try XCTUnwrap(map["MyModule.withTest<A>(named:_:)"])
        XCTAssertEqual(266, info.startLine, "Later declaration must replace the earlier range")
        XCTAssertEqual(268, info.endLine)
    }

    func testAsyncFunctionWithNoRecoverableSourceLinesOmittedWithoutCrash() throws {
        // If literally none of a function's chunks ever carry a real source line, it must
        // be silently omitted from the map rather than crashing or corrupting other entries.
        let body = """
                    0x0100 (0x0020) AsyncSuite.testNoLines() [FUNC, EXT, LENGTH, NameNList, MangledNameNList, Merged, NList, Dwarf]\(" ")
                        0x0100 (0x0020) /<compiler-generated>:0
                    0x0120 (0x0020) @objc AsyncSuite.testNoLines() [FUNC, LENGTH, NameNList, MangledNameNList, Merged, NList, Dwarf]\(" ")
                        0x0120 (0x0020) /<compiler-generated>:0
        """
        let url = try makeFixture(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let map = try FileLocator.extractFunctions(url)
        XCTAssertNil(map["AsyncSuite.testNoLines"])
    }
}
