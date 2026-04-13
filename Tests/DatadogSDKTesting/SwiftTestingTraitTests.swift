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
    func testRetryShouldFail() async throws {
        #expect(1 == 0, Comment(rawValue: Testing.Test.current!.ddName))
    }
    
    @Test
    func testRetryErrorIgnore() async throws {
        throw TestError.test(Testing.Test.current!.ddName)
    }
    
    @Test
    func testRetryErrorShouldFail() async throws {
        throw TestError.test(Testing.Test.current!.ddName)
    }
    
    @Test
    func testPass() async throws {
        #expect(1 == 1, Comment(rawValue: Testing.Test.current!.ddName))
    }
    
    @Test
    func testShouldFail() async throws {
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
func testFuncRetryErrorShouldFail() async throws {
    throw SwiftTestingTraitTests.TestError.test(Testing.Test.current!.ddName)
}

@Test(.observerTester, .datadogTesting)
func testFuncRegistration() async throws {
    #expect(Testing.Test.current?.ddSuite == "[\(URL(string: #file)!.deletingPathExtension().lastPathComponent)]")
}

#if compiler(>=6.3)
@Test(.observerTester, .datadogTesting)
func zzzzFuncCancel() async throws {
    try Testing.Test.cancel(Comment(rawValue: Testing.Test.current!.ddName))
}
#endif

private final class MockSwiftTestingObserver: SwiftTestingObserverType {
    func willStart(suite: borrowing SwiftTestingSuiteContext) async {}

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

    func willStart(group: borrowing SwiftTestingRetryGroupContext) async {}

    func didFinish(group: borrowing SwiftTestingRetryGroupContext) async {}

    func willStart(testRun test: borrowing SwiftTestingTestRunContext, with info: TestRunInfoStart) async {}

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
            let session = Mocks.SessionManager(provider: Mocks.Session.Provider(),
                                               config: .init(activeFeatures: [],
                                                             platform: DDTestMonitor.env.platform,
                                                             clock: DateClock(),
                                                             crash: nil,
                                                             command: nil,
                                                             service: "test-service",
                                                             metrics: [:],
                                                             log: Mocks.CatchLogger()),
                                               observer: SessionAndModuleObserver())
            DatadogSwiftTestingTrait.sharedSuiteProvider = SwiftTestingSuiteProvider(session: session,
                                                                                     observer: MockSwiftTestingObserver())
        }
    }
    
    func provideScope(for test: Testing.Test, testCase: Testing.Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        let issues: Synced<[String: Int]> = .init([:])
        let cancelled: Synced<[String: Bool]> = .init([:])
        
        do {
            try await withKnownIssue(isIntermittent: true) {
                try await function()
            } matching: { issue in
                if let err = issue.error as? SwiftTestingTraitTests.TestError {
                    issues.update { $0[err.name, default: 0] += 1 }
                    return true
                }
                if issue.comments.first?.rawValue.lowercased().contains("shouldfail") ?? false {
                    let name = issue.comments.first!.rawValue.components(separatedBy: " ").last!
                    issues.update { $0[name, default: 0] += 1 }
                    return true
                }
                return false
            }
        } catch {
            if error.isSwiftTestingSkip {
                let comment = try #require(Mirror(reflecting: error).descendant("comment") as? Comment).rawValue
                cancelled.update { $0[comment] = true }
            } else {
                throw error
            }
        }
        
        let suiteProvider = try #require(DatadogSwiftTestingTrait.sharedSuiteProvider as? SwiftTestingSuiteProvider)
        
        let tests = await suiteProvider.registry.registeredTests
        let suite = try #require(tests[test.ddModule]?[test.ddSuite])
        let session = try await #require(suiteProvider.session.session as? Mocks.Session)
        
        // check is module ended and if ended - stop the test session. This is the last test
        if session.modules.first?.value.duration ?? 0 > 0 {
            await suiteProvider.session.stop()
        }
        
        let statuses = try #require(session.modules[test.ddModule]?.suites[test.ddSuite])
        let errors = issues.value
        let cancels = cancelled.value
        
        let expected: [String: (status: [TestStatus], errors: Int?, cancelled: Bool?)] = [
            "scopingTraitIsApplied": ([.pass], nil, nil),
            "testSkip": ([.skip], nil, nil),
            "testRetryIgnore": (Array(repeating: .fail, count: 5), nil, nil),
            "testRetryShouldFail": (Array(repeating: .fail, count: 5), 1, nil),
            "testRetryErrorIgnore": (Array(repeating: .fail, count: 5), nil, nil),
            "testRetryErrorShouldFail": (Array(repeating: .fail, count: 5), 1, nil),
            "testPass": ([.pass], nil, nil),
            "testShouldFail": ([.fail], 1, nil),
            "testError": ([.fail], 1, nil),
            "testErrorIgnore": ([.fail], nil, nil),
            "testFuncRetryErrorShouldFail": (Array(repeating: .fail, count: 5), 1, nil),
            "testFuncRegistration": ([.pass], nil, nil),
            "testParameterized(p1:p2:)": (Array(repeating: .pass, count: 3), nil, nil),
            "zzzzFuncCancel": ([.skip], nil, true)
        ]
        
        // If we have a suite we should check for all tests.
        // If we have function we need check only for function, scope will be called for each
        let testsList = test.isSuite ? suite : [test.ddName]
        for test in testsList {
            let expect = try #require(expected[test])
            let status = try #require(statuses[test]).runs.map { $0.status }
            #expect(status == expect.status)
            #expect(errors[test] == expect.errors)
            #expect(cancels[test] == expect.cancelled)
        }
        
        let decoder = JSONDecoder()

        // Verify parameter tags on every run of the parameterized test.
        if test.isSuite, let paramGroup = statuses["testParameterized(p1:p2:)"] {
            for run in paramGroup.runs {
                #expect(run.tags[DDTestTags.testParameters] != nil)
            }
            let params = try paramGroup.runs.map {
                try $0.tags[DDTestTags.testParameters].map { try decoder.decode(TestParameters.self, from: $0.utf8Data) }
            }.sorted { g1, g2 in
                g1?.arguments.first?.value ?? "" < g2?.arguments.first?.value ?? ""
            }
            // Arguments are zip([1,2,3], ["1","2","3"]); the String value appears
            // with its surrounding quotes in the description, so it is JSON-escaped.
            let expectedParams: [TestParameters] = [
                [(name: "p1", value: "1", type: "Swift.Int"), (name: "p2", value:"\"1\"", type:"Swift.String")],
                [(name: "p1", value: "2", type: "Swift.Int"), (name: "p2", value:"\"2\"", type:"Swift.String")],
                [(name: "p1", value: "3", type: "Swift.Int"), (name: "p2", value:"\"3\"", type:"Swift.String")]
            ]
            for (run, expected) in zip(params, expectedParams) {
                #expect(run == expected)
            }
        }
    }
}

private struct TestParameters: Equatable, Codable, ExpressibleByArrayLiteral {
    typealias ArrayLiteralElement = (name: String, value: String, type: String)
    
    struct Argument: Equatable, Codable {
        let name: String
        let value: String
        let type: String
        
        init(_ t: (name: String, value: String, type: String)) {
            name = t.name; value = t.value; type = t.type
        }
    }
    
    let arguments: [Argument]
    
    init(arrayLiteral elements: (name: String, value: String, type: String)...) {
        arguments = elements.map(Argument.init)
    }
}

private extension Testing.Trait where Self == ObserverTesterTrait {
    static var observerTester: Self { Self() }
}
#endif
