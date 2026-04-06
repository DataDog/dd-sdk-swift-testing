/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogSDKTesting
import EventsExporter

#if canImport(Testing)
import Testing

@Suite(.observerTester, .datadogTesting)
struct SwiftTestingTraitTests {
    enum TestError: Error {
        case test(String)
        
        var name: String {
            switch self {
            case .test(let name): return name
            }
        }
    }
    
    @Test
    func scopingTraitIsApplied() async throws {
        #expect(Testing.Test.current?.ddSuite == "\(type(of: self))")
    }
    
    @Test
    func testSkip() async throws {
        #expect(1 == 0, Comment(rawValue: Testing.Test.current!.ddName))
    }
    
    @Test()
    func testRetryIgnore() async throws {
        #expect(1 == 0, Comment(rawValue: Testing.Test.current!.ddName))
    }
    
    @Test
    func testRetryFail() async throws {
        #expect(1 == 0, Comment(rawValue: Testing.Test.current!.ddName))
    }
    
    @Test
    func testRetryErrorIgnore() async throws {
        throw TestError.test(Testing.Test.current!.ddName)
    }
    
    @Test
    func testRetryErrorFail() async throws {
        throw TestError.test(Testing.Test.current!.ddName)
    }
    
    @Test
    func testPass() async throws {
        #expect(1 == 1, Comment(rawValue: Testing.Test.current!.ddName))
    }
    
    @Test
    func testFail() async throws {
        #expect(1 == 0, Comment(rawValue: Testing.Test.current!.ddName))
    }
    
    @Test
    func testError() async throws {
        throw TestError.test(Testing.Test.current!.ddName)
    }
    
    @Test
    func testErrorIgnore() async throws {
        throw TestError.test(Testing.Test.current!.ddName)
    }
    
    @Test(arguments: zip([1, 2, 3], ["1", "2", "3"]))
    func testParameterized(p1: Int, p2: String) async throws {
        #expect("\(p1)" == p2)
    }
}

@Test(.observerTester, .datadogTesting)
func testFuncRetryErrorFail() async throws {
    throw SwiftTestingTraitTests.TestError.test(Testing.Test.current!.ddName)
}

@Test(.observerTester, .datadogTesting)
func testFuncRegistration() async throws {
    #expect(Testing.Test.current?.ddSuite == "[\(URL(string: #file)!.deletingPathExtension().lastPathComponent)]")
}

private final class MockSwiftTestingObserver: SwiftTestingObserverType {
    nonisolated(unsafe) var isModuleEnded: Bool = false
    
    func willStart(session: any TestSession, with config: SessionConfig) async {}

    func willFinish(session: any TestSession, with config: SessionConfig) async {}

    func didFinish(session: any TestSession, with config: SessionConfig) async {
        // Cleanup
        DatadogSwiftTestingTrait.sharedSuiteProvider = nil
    }
    
    func willStart(module: any TestModule, with configuration: SessionConfig) async {}

    func willFinish(module: any TestModule, with configuration: SessionConfig) async {}

    func didFinish(module: any TestModule, with configuration: SessionConfig) async {
        isModuleEnded = true
    }

    func willStart(suite: borrowing SwiftTestingSuiteContext) async {
        let session = suite.suite.session as! Mocks.Session
        let module = suite.suite.module as! Mocks.Module
        session.add(module: module)
        module.add(suite: suite.suite as! Mocks.Suite)
    }

    func willFinish(suite: borrowing SwiftTestingSuiteContext) async {}

    func didFinish(suite: borrowing SwiftTestingSuiteContext, active: borrowing SwiftTestingSuiteContext?) async {}

    func willStart(test: borrowing SwiftTestingTestContext) async {}

    func didFinish(test: borrowing SwiftTestingTestContext) async {}

    func runGroupConfiguration(test: borrowing SwiftTestingTestContext) async -> (feature: FeatureId?, configuration: RetryGroupConfiguration) {
        if test.info.name.lowercased().contains("skip") {
            return ("skip_test", .skip(reason: "skip_test",
                                       configuration: .init(skipStatus: .init(canBeSkipped: true,
                                                                              markedUnskippable: false))))
        }
        if test.info.name.lowercased().contains("ignore") {
            return ("ignore_test", .retry(.init(skipStatus: .init(canBeSkipped: false, markedUnskippable: false),
                                                successStrategy: .alwaysSucceeded)))
        }
        return (nil, .retry(.init(skipStatus: .init(canBeSkipped: false, markedUnskippable: false))))
    }

    func willStart(group: borrowing SwiftTestingRetryGroupContext) async {
        let suite = group.test.suite.suite as! Mocks.Suite
        let testName = group.test.info.name
        let testGroup = suite.tests[testName] ?? .init(name: testName, suite: suite, unskippable: false)
        suite.add(group: testGroup)
    }

    func didFinish(group: borrowing SwiftTestingRetryGroupContext) async {}

    func willStart(testRun test: borrowing SwiftTestingTestRunContext, with info: TestRunInfoStart) async {
        let suite = test.test.suite.suite as! Mocks.Suite
        let group = suite.tests[test.test.info.name]!
        group.add(run: test.testRun as! Mocks.Test)
    }

    func shouldSuppressError(for testRun: borrowing SwiftTestingTestRunContext, with info: TestRunInfoStart) -> Bool {
        let name = testRun.info.name.lowercased()
        if name.contains("ignore") || name.contains("retry") {
            return true
        }
        return false
    }

    func willFinish(testRun test: borrowing SwiftTestingTestRunContext,
                    withStatus status: SwiftTestingTestStatus,
                    andInfo info: TestRunInfoEnd) async -> (feature: FeatureId?, status: RetryStatus) {
        let suite = test.test.suite.suite as! Mocks.Suite
        let group = suite.tests[test.test.info.name]!
        let count = group.runs.count
        let name = test.info.name.lowercased()
        let ignore: RetryStatus.ErrorsStatus = name.contains("ignore") ? .suppressed(reason: "suppress_test") : .unsuppressed
        guard name.contains("retry") else {
            return (nil, .end(errors: ignore))
        }
        return count < 5 ? ("retry", .retry(reason: "retry_test", errors: .suppressed(reason: "retry_test"))) : (nil, .end(errors: ignore))
    }

    func didFinish(testRun test: borrowing SwiftTestingTestRunContext, with info: TestRunInfoEnd) async {}
}

private struct ObserverTesterTrait: SuiteTrait, TestTrait, TestScoping {
    let isRecursive: Bool = false
    
    func prepare(for test: Testing.Test) async throws {
        if DatadogSwiftTestingTrait.sharedSuiteProvider == nil {
            let session = Mocks.SessionManager(provider: Mocks.Session.Provider(), config: .init(activeFeatures: [],
                                                                                                 workspacePath: DDTestMonitor.env.workspacePath,
                                                                                                 codeOwners: nil,
                                                                                                 bundleFunctions: .init(),
                                                                                                 platform: DDTestMonitor.env.platform,
                                                                                                 clock: DateClock(),
                                                                                                 crash: nil,
                                                                                                 command: nil,
                                                                                                 service: "test-service",
                                                                                                 metrics: [:],
                                                                                                 log: Mocks.CatchLogger()))
            DatadogSwiftTestingTrait.sharedSuiteProvider = SwiftTestingSuiteProvider(session: session,
                                                                                     observer: MockSwiftTestingObserver())
        }
    }
    
    func provideScope(for test: Testing.Test, testCase: Testing.Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        let issues: Synced<[String: Int]> = .init([:])
        try await withKnownIssue(isIntermittent: true) {
            try await function()
        } matching: { issue in
            if let err = issue.error as? SwiftTestingTraitTests.TestError {
                issues.update { $0[err.name, default: 0] += 1 }
                return true
            }
            if issue.comments.first?.rawValue.lowercased().contains("fail") ?? false {
                issues.update { $0[issue.comments.first!.rawValue, default: 0] += 1 }
                return true
            }
            return false
        }
        
        let suiteProvider = try #require(DatadogSwiftTestingTrait.sharedSuiteProvider as? SwiftTestingSuiteProvider)
        
        let observer = try #require(suiteProvider.observer as? MockSwiftTestingObserver)
        let tests = await suiteProvider.registry.registeredTests
        let suite = try #require(tests[test.ddModule]?[test.ddSuite])
        let session = try await #require(suiteProvider.session.session as? Mocks.Session)
        
        if observer.isModuleEnded {
            await suiteProvider.session.stop()
        }
        
        let statuses = try #require(session.modules[test.ddModule]?.suites[test.ddSuite])
        let errors = issues.value
        
        let expected: [String: (status: [TestStatus], errors: Int?)] = [
            "scopingTraitIsApplied": ([.pass], nil),
            "testSkip": ([.skip], nil),
            "testRetryIgnore": (Array(repeating: .fail, count: 5), nil),
            "testRetryFail": (Array(repeating: .fail, count: 5), 1),
            "testRetryErrorIgnore": (Array(repeating: .fail, count: 5), nil),
            "testRetryErrorFail": (Array(repeating: .fail, count: 5), 1),
            "testPass": ([.pass], nil),
            "testFail": ([.fail], 1),
            "testError": ([.fail], 1),
            "testErrorIgnore": ([.fail], nil),
            "testFuncRetryErrorFail": (Array(repeating: .fail, count: 5), 1),
            "testFuncRegistration": ([.pass], nil),
            "testParameterized(p1:p2:)": (Array(repeating: .pass, count: 3), nil)
        ]
        
        // If we have a suite we should check for all tests.
        // If we have function we need check only for function, scope will be called for each
        let testsList = test.isSuite ? suite : [test.ddName]
        for test in testsList {
            let expect = try #require(expected[test])
            let status = try #require(statuses[test]).runs.map { $0.status }
            #expect(status == expect.status)
            #expect(errors[test] == expect.errors)
        }
        
        let decoder = JSONDecoder()

        // Verify parameter tags on every run of the parameterized test.
        if test.isSuite, let paramGroup = statuses["testParameterized(p1:p2:)"] {
            for run in paramGroup.runs {
                #expect(run.tags[DDTestTags.testParameters] != nil)
            }
            // Arguments are zip([1,2,3], ["1","2","3"]); the String value appears
            // with its surrounding quotes in the description, so it is JSON-escaped.
            let expectedParams = [
                try decoder.decode(JSONGeneric.self, from: #"{"arguments":[{"name":"p1","value":"1","type":"Swift.Int"},{"name":"p2","value":"\"1\"","type":"Swift.String"}]}"#.utf8Data),
                try decoder.decode(JSONGeneric.self, from: #"{"arguments":[{"name":"p1","value":"2","type":"Swift.Int"},{"name":"p2","value":"\"2\"","type":"Swift.String"}]}"#.utf8Data),
                try decoder.decode(JSONGeneric.self, from: #"{"arguments":[{"name":"p1","value":"3","type":"Swift.Int"},{"name":"p2","value":"\"3\"","type":"Swift.String"}]}"#.utf8Data)
            ]
            for (run, expected) in zip(paramGroup.runs, expectedParams) {
                let runParams = try run.tags[DDTestTags.testParameters].map { try decoder.decode(JSONGeneric.self, from: $0.utf8Data) }
                #expect(runParams == expected)
            }
        }
    }
}

private extension Testing.Trait where Self == ObserverTesterTrait {
    static var observerTester: Self { Self() }
}
#endif
