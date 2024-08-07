/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@_implementationOnly import OpenTelemetryApi
@_implementationOnly import OpenTelemetrySdk
@testable import DatadogSDKTesting
import XCTest

class IntegrationTestsRunner: XCTestCase {
    var testOutputFile: URL!
    var app: XCUIApplication!
    var recoveredSpans: [SimpleSpanData]!
    var testSpan: SimpleSpanData!
    var attrib: [String: String]!

    static let testNameRegex = try! NSRegularExpression(pattern: "([\\w]+) ([\\w]+)", options: .caseInsensitive)

    override func setUpWithError() throws {
        continueAfterFailure = false

        guard let namematch = IntegrationTestsRunner.testNameRegex.firstMatch(in: self.name, range: NSRange(location: 0, length: self.name.count)),
              let nameRange = Range(namematch.range(at: 2), in: self.name)
        else {
            return
        }
        let testName = String(self.name[nameRange])
        let testDesiredClass = testName.dropFirst(4)

        testOutputFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(testName).appendingPathExtension("json")
        FileManager.default.createFile(atPath: testOutputFile.path, contents: nil, attributes: nil)

        app = XCUIApplication()
        app.launchEnvironment["TEST_CLASS"] = "IntegrationTestsApp.\(testDesiredClass)"
        app.launchEnvironment["SRCROOT"] = ProcessInfo.processInfo.environment["SRCROOT"]
        app.launchEnvironment["TEST_OUTPUT_FILE"] = testOutputFile.path
        app.launch()
        let returnSpans = waitForTestResult()

        recoveredSpans = try XCTUnwrap(returnSpans)
        testSpan = try XCTUnwrap(recoveredSpans.first {
            $0.stringAttributes["type"] == "test"
        })
        attrib = testSpan.stringAttributes
    }

    override func tearDownWithError() throws {
        validateGenericAttributes()
    }

    func waitForTestResult() -> [SimpleSpanData]? {
        guard let outputFile = FileHandle(forReadingAtPath: testOutputFile.path) else {
            XCTFail("internal test didn export file")
            return nil
        }
        outputFile.waitForDataInBackgroundAndNotify()
        sleep(1)
        let resultSpans = try? JSONDecoder().decode([SimpleSpanData].self, from: outputFile.availableData)
        return resultSpans
    }

    func testBasicPass() throws {
        XCTAssertEqual(recoveredSpans.count, 1)
        XCTAssertEqual(attrib[DDTestTags.testStatus], DDTagValues.statusPass)
        XCTAssertEqual(attrib[DDGenericTags.resource], "BasicPass.testBasicPass")
        XCTAssertEqual(attrib[DDTestTags.testName], "testBasicPass")
        XCTAssertEqual(attrib[DDTestTags.testSuite], "BasicPass")
        XCTAssertEqual(attrib[DDTestTags.testType], "test")
    }

    func testBasicSkip() throws {
        XCTAssertEqual(recoveredSpans.count, 1)
        XCTAssertEqual(testSpan.stringAttributes[DDTestTags.testStatus], DDTagValues.statusSkip)
        XCTAssertEqual(attrib[DDGenericTags.resource], "BasicSkip.testBasicSkip")
        XCTAssertEqual(attrib[DDTestTags.testName], "testBasicSkip")
        XCTAssertEqual(attrib[DDTestTags.testSuite], "BasicSkip")
        XCTAssertEqual(attrib[DDTestTags.testType], "test")
    }

    func testBasicError() throws {
        XCTAssertEqual(recoveredSpans.count, 1)
        XCTAssertEqual(attrib[DDTestTags.testStatus], DDTagValues.statusFail)
        XCTAssertEqual(attrib[DDGenericTags.resource], "BasicError.testBasicError")
        XCTAssertEqual(attrib[DDTestTags.testName], "testBasicError")
        XCTAssertEqual(attrib[DDTestTags.testSuite], "BasicError")
        XCTAssertEqual(attrib[DDTestTags.testType], "test")
    }

    func testAsynchronousPass() throws {
        XCTAssertEqual(recoveredSpans.count, 2)
        XCTAssertEqual(attrib[DDTestTags.testStatus], DDTagValues.statusPass)
        XCTAssertEqual(attrib[DDGenericTags.resource], "AsynchronousPass.testAsynchronousPass")
        XCTAssertEqual(attrib[DDTestTags.testName], "testAsynchronousPass")
        XCTAssertEqual(attrib[DDTestTags.testSuite], "AsynchronousPass")
        XCTAssertEqual(attrib[DDTestTags.testType], "test")
    }

    func testAsynchronousSkip() throws {
        XCTAssertEqual(recoveredSpans.count, 2)
        XCTAssertEqual(attrib[DDTestTags.testStatus], DDTagValues.statusSkip)
        XCTAssertEqual(attrib[DDGenericTags.resource], "AsynchronousSkip.testAsynchronousSkip")
        XCTAssertEqual(attrib[DDTestTags.testName], "testAsynchronousSkip")
        XCTAssertEqual(attrib[DDTestTags.testSuite], "AsynchronousSkip")
        XCTAssertEqual(attrib[DDTestTags.testType], "test")
    }

    func testAsynchronousError() throws {
        XCTAssertEqual(recoveredSpans.count, 2)
        XCTAssertEqual(attrib[DDTestTags.testStatus], DDTagValues.statusFail)
        XCTAssertEqual(attrib[DDGenericTags.resource], "AsynchronousError.testAsynchronousError")
        XCTAssertEqual(attrib[DDTestTags.testName], "testAsynchronousError")
        XCTAssertEqual(attrib[DDTestTags.testSuite], "AsynchronousError")
        XCTAssertEqual(attrib[DDTestTags.testType], "test")
    }

    func testNetworkIntegration() throws {
        XCTAssertEqual(recoveredSpans.count, 2)
        XCTAssertEqual(attrib[DDGenericTags.resource], "NetworkIntegration.testNetworkIntegration")
        XCTAssertEqual(attrib[DDTestTags.testName], "testNetworkIntegration")
        XCTAssertEqual(attrib[DDTestTags.testSuite], "NetworkIntegration")
        XCTAssertEqual(attrib[DDTestTags.testType], "test")
        let networkSpan = try XCTUnwrap(recoveredSpans.first { $0 != testSpan })
        XCTAssertEqual(networkSpan.name, "HTTP GET")
        XCTAssertEqual(networkSpan.stringAttributes[SemanticAttributes.netPeerName.rawValue], "httpbin.org")
        XCTAssertEqual(networkSpan.stringAttributes[SemanticAttributes.httpUrl.rawValue], "https://httpbin.org/get")
        XCTAssertEqual(networkSpan.stringAttributes[SemanticAttributes.httpStatusCode.rawValue], "200")
        XCTAssertEqual(networkSpan.stringAttributes[SemanticAttributes.httpMethod.rawValue], "GET")
        XCTAssertEqual(networkSpan.stringAttributes[SemanticAttributes.httpTarget.rawValue], "/get")
        XCTAssertEqual(networkSpan.stringAttributes[SemanticAttributes.httpScheme.rawValue], "https")
        XCTAssertNotNil(networkSpan.stringAttributes["http.request.headers"])
        XCTAssertNotNil(networkSpan.stringAttributes["http.response.headers"])
        XCTAssertNotNil(networkSpan.stringAttributes["http.request.payload"])
        XCTAssertNotNil(networkSpan.stringAttributes["http.response.payload"])
    }

    func testBenchmark() throws {
        XCTAssertEqual(recoveredSpans.count, 1)
        XCTAssertEqual(attrib[DDGenericTags.resource], "Benchmark.testBenchmark")
        XCTAssertEqual(attrib[DDTestTags.testName], "testBenchmark")
        XCTAssertEqual(attrib[DDTestTags.testSuite], "Benchmark")
        XCTAssertEqual(attrib[DDTestTags.testType], "benchmark")

        let durationBenchmark = DDBenchmarkTags.benchmark + "." + DDBenchmarkMeasuresTags.duration + "."

        XCTAssertGreaterThan(Int(attrib[durationBenchmark + DDBenchmarkTags.benchmarkRun] ?? "0") ?? 0, 0)
        XCTAssertNotNil(attrib[durationBenchmark + DDBenchmarkTags.benchmarkMean])
        XCTAssertGreaterThan(Int(attrib[durationBenchmark + DDBenchmarkTags.statisticsN] ?? "0") ?? 0, 0)
        XCTAssertNotNil(attrib[durationBenchmark + DDBenchmarkTags.statisticsMax])
        XCTAssertNotNil(attrib[durationBenchmark + DDBenchmarkTags.statisticsMin])
        XCTAssertNotNil(attrib[durationBenchmark + DDBenchmarkTags.statisticsMean])
        XCTAssertNotNil(attrib[durationBenchmark + DDBenchmarkTags.statisticsMedian])
        XCTAssertNotNil(attrib[durationBenchmark + DDBenchmarkTags.statisticsStdDev])
        XCTAssertNotNil(attrib[durationBenchmark + DDBenchmarkTags.statisticsStdErr])
        XCTAssertNotNil(attrib[durationBenchmark + DDBenchmarkTags.statisticsKurtosis])
        XCTAssertNotNil(attrib[durationBenchmark + DDBenchmarkTags.statisticsSkewness])
        XCTAssertNotNil(attrib[durationBenchmark + DDBenchmarkTags.statisticsP99])
        XCTAssertNotNil(attrib[durationBenchmark + DDBenchmarkTags.statisticsP95])
        XCTAssertNotNil(attrib[durationBenchmark + DDBenchmarkTags.statisticsP90])
    }

    func validateGenericAttributes() {
        XCTAssertEqual(attrib[DDGenericTags.type], "test")
        XCTAssertEqual(attrib[DDTestTags.testModule], "IntegrationTestsApp")
        XCTAssertEqual(attrib[DDTestTags.testFramework], "XCTest")
        XCTAssertEqual(attrib[DDTestTags.testSourceFile], "IntegrationTests/App/IntegrationTests.swift")
        XCTAssertGreaterThan(Int(attrib[DDTestTags.testSourceStartLine] ?? "0") ?? 0, 0)
        XCTAssertGreaterThan(Int(attrib[DDTestTags.testSourceEndLine] ?? "0") ?? 0, 0)
        XCTAssertEqual(attrib[DDOSTags.osPlatform], PlatformUtils.getRunningPlatform())
        XCTAssertEqual(attrib[DDOSTags.osArchitecture], PlatformUtils.getPlatformArchitecture())
        XCTAssertEqual(attrib[DDOSTags.osVersion], PlatformUtils.getDeviceVersion())
        XCTAssertEqual(attrib[DDRuntimeTags.runtimeName], "Xcode")
        XCTAssertEqual(attrib[DDDeviceTags.deviceName], PlatformUtils.getDeviceName())
        XCTAssertEqual(attrib[DDDeviceTags.deviceModel], PlatformUtils.getDeviceModel())
        XCTAssertNotNil(attrib[DDGitTags.gitRepository])
        XCTAssertNotNil(attrib[DDGitTags.gitBranch] ?? attrib[DDGitTags.gitTag])
        XCTAssertNotNil(attrib[DDGitTags.gitCommit])
        XCTAssertNotNil(attrib[DDGitTags.gitCommitMessage])
        XCTAssertNotNil(attrib[DDGitTags.gitAuthorName])
        XCTAssertNotNil(attrib[DDGitTags.gitAuthorEmail])
        XCTAssertNotNil(attrib[DDGitTags.gitAuthorDate])
        XCTAssertNotNil(attrib[DDGitTags.gitCommitterName])
        XCTAssertNotNil(attrib[DDGitTags.gitCommitterEmail])
        XCTAssertNotNil(attrib[DDGitTags.gitCommitterDate])
    }
}
