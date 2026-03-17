//
//  SwiftTestingTraitTests.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 13/03/2026.
//

import Testing
import Foundation
@testable import DatadogSDKTesting

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
    func willStart(suite: any SwiftTestingSuiteContextType) async {
        let session = suite.suite.session as! Mocks.Session
        let module = suite.suite.module as! Mocks.Module
        session.add(module: module)
        module.add(suite: suite.suite as! Mocks.Suite)
    }

    func didFinish(suite: any SwiftTestingSuiteContextType) async {}

    func willStart(test: any SwiftTestingTestContextType) async {}

    func didFinish(test: any SwiftTestingTestContextType) async {}

    func runGroupConfiguration(test: any SwiftTestingTestContextType) async -> RetryGroupConfiguration {
        if test.info.name.lowercased().contains("skip") {
            return .skip(reason: "skip_test", configuration: .init(skipStatus: .init(canBeSkipped: true, markedUnskippable: false)))
        }
        return .retry(.init(skipStatus: .init(canBeSkipped: false, markedUnskippable: false)))
    }

    func willStart(group: any SwiftTestingRetryGroupContextType) async {
        let suite = group.test.suite.suite as! Mocks.Suite
        let mGroup = Mocks.Group(name: group.test.info.name, suite: suite, unskippable: false)
        suite.add(group: mGroup)
    }

    func didFinish(group: any SwiftTestingRetryGroupContextType) async {}

    func willStart(testRun test: any SwiftTestingTestRunContextType) async {
        let suite = test.test.suite as! Mocks.Suite
        let group = suite.tests[test.test.name]!
        group.add(run: test.test as! Mocks.Test)
    }

    func shouldSuppressError(for testRun: some SwiftTestingTestRunContextType) -> Bool {
        let name = testRun.info.name.lowercased()
        if name.contains("ignore") || name.contains("retry") {
            return true
        }
        return false
    }

    func willFinish(testRun test: any SwiftTestingTestRunContextType, with status: SwiftTestingTestStatus) async -> SwiftTestingTestRunRetry {
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

    func didFinish(testRun test: any SwiftTestingTestRunContextType) async {}
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
        defer {
            DatadogSwiftTestingTrait.sharedSuiteProvider = nil
        }
        
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
        ]
        
        for test in suite {
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
