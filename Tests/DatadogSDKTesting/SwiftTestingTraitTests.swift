/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogSDKTesting

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
        #expect(Testing.Test.current?.suite == "\(type(of: self))")
    }
    
    @Test
    func testSkip() async throws {
        #expect(1 == 0, Comment(rawValue: Testing.Test.current!.name))
    }
    
    @Test()
    func testRetryIgnore() async throws {
        #expect(1 == 0, Comment(rawValue: Testing.Test.current!.name))
    }
    
    @Test
    func testRetryFail() async throws {
        #expect(1 == 0, Comment(rawValue: Testing.Test.current!.name))
    }
    
    @Test
    func testRetryErrorIgnore() async throws {
        throw TestError.test(Testing.Test.current!.name)
    }
    
    @Test
    func testRetryErrorFail() async throws {
        throw TestError.test(Testing.Test.current!.name)
    }
    
    @Test
    func testPass() async throws {
        #expect(1 == 1, Comment(rawValue: Testing.Test.current!.name))
    }
    
    @Test
    func testFail() async throws {
        #expect(1 == 0, Comment(rawValue: Testing.Test.current!.name))
    }
    
    @Test
    func testError() async throws {
        throw TestError.test(Testing.Test.current!.name)
    }
    
    @Test
    func testErrorIgnore() async throws {
        throw TestError.test(Testing.Test.current!.name)
    }
    
    @Test(arguments: zip([1, 2, 3], ["1", "2", "3"]))
    func testParameterized(p1: Int, p2: String) async throws {
        #expect("\(p1)" == p2)
    }
}

@Test(.observerTester, .datadogTesting)
func testFuncRetryErrorFail() async throws {
    throw SwiftTestingTraitTests.TestError.test(Testing.Test.current!.name)
}

@Test(.observerTester, .datadogTesting)
func testFuncRegistration() async throws {
    #expect(Testing.Test.current?.suite == "[\(URL(string: #file)!.deletingPathExtension().lastPathComponent)]")
}


private final class MockSwiftTestingSessionProvider: TestSessionProvider {
    func startSession() async throws -> any TestModuleProvider & TestSession {
        Mocks.Session(name: "TestSession")
    }
}

private final class MockSwiftTestingObserver: SwiftTestingObserverType {
    func willStart(module: any TestModule) async {}
    
    func didFinish(module: any TestModule) async {
        // Cleanup
        DatadogSwiftTestingTrait.sharedSuiteProvider = nil
    }
    
    func willStart(suite: borrowing SwiftTestingSuiteContext) async {
        let session = suite.suite.session as! Mocks.Session
        let module = suite.suite.module as! Mocks.Module
        session.add(module: module)
        module.add(suite: suite.suite as! Mocks.Suite)
    }

    func didFinish(suite: borrowing SwiftTestingSuiteContext) async {}

    func willStart(test: borrowing SwiftTestingTestContext) async {}

    func didFinish(test: borrowing SwiftTestingTestContext) async {}

    func runGroupConfiguration(test: borrowing SwiftTestingTestContext) async -> RetryGroupConfiguration {
        if test.info.name.lowercased().contains("skip") {
            return .skip(reason: "skip_test", configuration: .init(skipStatus: .init(canBeSkipped: true, markedUnskippable: false)))
        }
        return .retry(.init(skipStatus: .init(canBeSkipped: false, markedUnskippable: false)))
    }

    func willStart(group: borrowing SwiftTestingRetryGroupContext) async {
        let suite = group.test.suite.suite as! Mocks.Suite
        let testName = group.test.info.name
        let testGroup = suite.tests[testName] ?? .init(name: testName, suite: suite, unskippable: false)
        suite.add(group: testGroup)
    }

    func didFinish(group: borrowing SwiftTestingRetryGroupContext) async {}

    func willStart(testRun test: borrowing SwiftTestingTestRunContext) async {
        let suite = test.test.suite as! Mocks.Suite
        let group = suite.tests[test.test.name]!
        group.add(run: test.test as! Mocks.Test)
    }

    func shouldSuppressError(for testRun: borrowing SwiftTestingTestRunContext) -> Bool {
        let name = testRun.info.name.lowercased()
        if name.contains("ignore") || name.contains("retry") {
            return true
        }
        return false
    }

    func willFinish(testRun test: borrowing SwiftTestingTestRunContext, with status: SwiftTestingTestStatus) async -> SwiftTestingTestRunRetry {
        let suite = test.test.suite as! Mocks.Suite
        let group = suite.tests[test.test.name]!
        let count = group.runs.count
        let name = test.info.name.lowercased()
        let ignore: RetryStatus.ErrorsStatus = name.contains("ignore") ? .suppressed(reason: "suppress_test") : .unsuppressed
        guard name.contains("retry") else {
            return .retry(.end(errors: ignore))
        }
        return count < 5 ? .retry(.retry(reason: "retry_test", errors: .suppressed(reason: "retry_test"))) : .retry(.end(errors: ignore))
    }

    func didFinish(testRun test: borrowing SwiftTestingTestRunContext) async {}
}

private struct ObserverTesterTrait: SuiteTrait, TestTrait, TestScoping {
    let isRecursive: Bool = false
    
    func prepare(for test: Testing.Test) async throws {
        if DatadogSwiftTestingTrait.sharedSuiteProvider == nil {
            DatadogSwiftTestingTrait.sharedSuiteProvider = SwiftTestingSuiteProvider(provider: MockSwiftTestingSessionProvider(),
                                                                                     observer: MockSwiftTestingObserver())
        }
    }
    
    func provideScope(for test: Testing.Test, testCase: Testing.Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        let issues: Synced<[String: Int]> = .init([:])
        try await withKnownIssue(isIntermittent: true) {
            try await function()
        } matching: { issue in
            if let err = issue.error as? SwiftTestingTraitTests.TestError {
                issues.update { $0.get(key: err.name, or: 0) { $0 += 1 } }
                return true
            } else if let err = issue.error as? DatadogSwiftTestingTrait.TestIssue {
                let test: String
                if let err = err.error as? SwiftTestingTraitTests.TestError {
                    test = err.name
                } else {
                    test = err.comments.first!.rawValue
                }
                issues.update { $0.get(key: test, or: 0) { $0 += 1 } }
                return true
            } else if let err = issue.error as? DatadogSwiftTestingTrait.TestIssues {
                let test: String
                if let err = err.issues.first!.error as? SwiftTestingTraitTests.TestError {
                    test = err.name
                } else {
                    test = err.issues.first!.comments.first!.rawValue
                }
                issues.update { $0.get(key: test, or: 0) { $0 += 1 } }
                return true
            }
            if issue.comments.first?.rawValue.lowercased().contains("fail") ?? false {
                issues.update { $0.get(key: issue.comments.first!.rawValue, or: 0) { $0 += 1 } }
                return true
            }
            return false
        }
        
        let suiteProvider = try #require(DatadogSwiftTestingTrait.sharedSuiteProvider as? SwiftTestingSuiteProvider)
        
        let tests = await suiteProvider.registry.registeredTests
        let suite = try #require(tests[test.module]?[test.suite])
        
        let session = try await #require(suiteProvider.session as? Mocks.Session)
        
        let statuses = try #require(session.modules[test.module]?.suites[test.suite])
        let errors = issues.value
        
        let expected: [String: (status: [SwiftTestingTestStatus], errors: Int?)] = [
            "scopingTraitIsApplied()": ([.passed], nil),
            "testSkip()": ([.skipped(reason: "skip_test")], nil),
            "testRetryIgnore()": (Array(repeating: .failed, count: 5), nil),
            "testRetryFail()": (Array(repeating: .failed, count: 5), 1),
            "testRetryErrorIgnore()": (Array(repeating: .failed, count: 5), nil),
            "testRetryErrorFail()": (Array(repeating: .failed, count: 5), 1),
            "testPass()": ([.passed], nil),
            "testFail()": ([.failed], 1),
            "testError()": ([.failed], 1),
            "testErrorIgnore()": ([.failed], nil),
            "testFuncRetryErrorFail()": (Array(repeating: .failed, count: 5), 1),
            "testFuncRegistration()": ([.passed], nil),
            "testParameterized(p1:p2:)": (Array(repeating: .passed, count: 3), nil)
        ]
        
        // If we have a suite we should check for all tests.
        // If we have function we need check only for function, scope will be called for each
        let testsList = test.isSuite ? suite : [test.name]
        for test in testsList {
            let expect = try #require(expected[test])
            let status = try #require(statuses[test]).runs.map { $0.status }
            #expect(status == expect.status.map { $0.testStatus })
            #expect(errors[test] == expect.errors)
        }
    }
}

private extension Testing.Trait where Self == ObserverTesterTrait {
    static var observerTester: Self { Self() }
}
#endif
