//
//  SwiftTestingTraitTests.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 13/03/2026.
//

import Testing
import Foundation
@testable import DatadogSDKTesting

@Suite(.initObserver, .datadogTesting)
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
        let provider = try #require(DatadogSwiftTestingTrait.sharedSuiteProvider as? SwiftTestingSuiteProvider)
        let tests = observer.tests.value
        let suite = try #require(tests[Testing.Test.current!.module]?[Testing.Test.current!.suite])
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

@Test(.initObserver, .datadogTesting)
func testFuncRetryErrorFail() async throws {
    throw SwiftTestingTraitTests.TestError.test(Testing.Test.current!.name)
}

@Test(.initObserver, .datadogTesting)
func testFuncRegistration() async throws {
    #expect(Testing.Test.current?.suite == "[\(URL(string: #file)!.deletingPathExtension().lastPathComponent)]")
}


private final class MockSwiftTestingSessionProvider: TestSessionProvider {
    func startSession() async throws -> any TestModuleProvider & TestSession {
        Mocks.Session(name: "TestSession")
    }
}

private final class MockSwiftTestingObserver: SwiftTestingObserverType {
    let tests: Synced<[String: [String: [String: [SwiftTestingTestStatus]]]]> = .init([:])
    
    func register(test: some SwiftTestingTest) async throws {
        tests.update { tests in
            tests.get(key: test.module, or: [:]) { module in
                if test.isSuite {
                    if module[test.suite] == nil {
                        module[test.suite] = [:]
                    }
                } else {
                    module.get(key: test.suite, or: [:]) { suite in
                        suite[test.name] = []
                    }
                }
            }
        }
    }
    
    func willRun(testRun test: some SwiftTestingTestRun) async throws -> RetryGroupConfiguration {
        if test.name.lowercased().contains("skip") {
            return .skip(reason: "skip_test", configuration: .init(skipStatus: .init(canBeSkipped: true, markedUnskippable: false)))
        }
        return .retry(.init(skipStatus: .init(canBeSkipped: false, markedUnskippable: false)))
    }
    
    func shouldSuppressError(testRun test: some SwiftTestingTestRun) -> Bool {
        let name = test.name.lowercased()
        if name.contains("ignore") || name.contains("retry") {
            return true
        }
        return false
    }
    
    func didRun(testRun test: some SwiftTestingTestRun, status: SwiftTestingTestStatus) async throws -> RetryStatus {
        let count = tests.update { tests in
            var runs = tests[test.module]![test.suite]![test.name]!
            runs.append(status)
            tests[test.module]![test.suite]![test.name] = runs
            return runs.count
        }
        let name = test.name.lowercased()
        let ignore: RetryStatus.ErrorsStatus = name.contains("ignore") ? .suppressed(reason: "suppress_test") : .unsuppressed
        guard name.contains("retry") else {
            return .end(errors: ignore)
        }
        return count < 5 ? .retry(reason: "retry_test", errors: .suppressed(reason: "retry_test")) : .end(errors: ignore)
    }
}

private struct ObserverInitScopingTrait: SuiteTrait, TestTrait, TestScoping {
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
            } else if let err = issue.error as? TestExecutionFailedError {
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
        
        let observer = try #require(DatadogSwiftTestingScopingTrait.sharedObserver as? MockSwiftTestingObserver)
        let tests = observer.tests.value
        let suite = try #require(tests[test.module]?[test.suite])
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
        
        for (test, status) in suite {
            let expect = try #require(expected[test])
            #expect(status == expect.status)
            #expect(errors[test] == expect.errors)
        }
    }
}

private extension Testing.Trait where Self == ObserverInitScopingTrait {
    static var initObserver: Self { Self() }
}
