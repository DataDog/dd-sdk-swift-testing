//
//  SwiftTestingTraitTests.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 13/03/2026.
//

import Testing
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
        let observer = DatadogSwiftTestingScopingTrait.mockObserver
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

private final class MockSwiftTestingObserver: SwiftTestingObserverType {
    let tests: Synced<[String: [String: [String: Int]]]> = .init([:])
    
    func register(test: some SwiftTestingTest) async throws {
        tests.update { tests in
            tests.get(key: test.module, or: [:]) { module in
                if test.isSuite {
                    if module[test.suite] == nil {
                        module[test.suite] = [:]
                    }
                } else {
                    module.get(key: test.suite, or: [:]) { suite in
                        suite[test.name] = 0
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
            let count = tests[test.module]![test.suite]![test.name]! + 1
            tests[test.module]![test.suite]![test.name] = count
            return count
        }
        let name = test.name.lowercased()
        let ignore: RetryStatus.ErrorsStatus = name.contains("ignore") ? .suppressed(reason: "suppress_test") : .unsuppressed
        guard name.contains("retry") else {
            return .end(errors: ignore)
        }
        return count < 5 ? .retry(reason: "retry_test", errors: .suppressed(reason: "retry_test")) : .end(errors: ignore)
    }
    
    
}

private struct ObserverInitScopingTrait: SuiteTrait, TestScoping {
    let isRecursive: Bool = false
    
    func prepare(for test: Testing.Test) async throws {
        if DatadogSwiftTestingScopingTrait.sharedObserver == nil {
            DatadogSwiftTestingScopingTrait.sharedObserver = MockSwiftTestingObserver()
        }
    }
    
    func provideScope(for test: Testing.Test, testCase: Testing.Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        defer {
            DatadogSwiftTestingScopingTrait.sharedObserver = nil
        }
        
        let issues: Synced<[String: Testing.Issue]> = .init([:])
        try await withKnownIssue(isIntermittent: true) {
            try await function()
        } matching: { issue in
            if let err = issue.error as? SwiftTestingTraitTests.TestError {
                issues.update { $0[err.name] = issue }
                return true
            } else if let err = issue.error as? TestExecutionFailedError {
                let test = err.issues.first!.comments.first!.rawValue
                issues.update { $0[test] = issue }
                return true
            }
            return issue.comments.first?.rawValue.contains("fail") ?? false
        }
    }
}

private extension DatadogSwiftTestingScopingTrait {
    static var mockObserver: MockSwiftTestingObserver {
        sharedObserver! as! MockSwiftTestingObserver
    }
}

private extension Testing.Trait where Self == ObserverInitScopingTrait {
    static var initObserver: Self { Self() }
}
