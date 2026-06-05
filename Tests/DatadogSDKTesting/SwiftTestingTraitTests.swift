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
        let test = try #require(Mocks.Test.active as? Mocks.Test)
        let framework = test.suite.testFramework
        #expect(framework.name == "Testing")
        #expect(framework.version == PlatformUtils.getSwiftTestingVersion())
    }

    @Test
    func testSkip() async throws {
        #expect(1 == 0, Comment(rawValue: Testing.Test.current!.ddFullName))
    }

    @Test()
    func testRetryIgnore() async throws {
        #expect(1 == 0, Comment(rawValue: Testing.Test.current!.ddFullName))
    }

    @Test
    func testRetryShouldFail() async throws {
        #expect(1 == 0, Comment(rawValue: Testing.Test.current!.ddFullName))
    }

    @Test
    func testRetryErrorIgnore() async throws {
        throw TestError.test(Testing.Test.current!.ddFullName)
    }

    @Test
    func testRetryErrorShouldFail() async throws {
        throw TestError.test(Testing.Test.current!.ddFullName)
    }

    @Test
    func testPass() async throws {
        #expect(1 == 1, Comment(rawValue: Testing.Test.current!.ddFullName))
    }

    @Test
    func testShouldFail() async throws {
        #expect(1 == 0, Comment(rawValue: Testing.Test.current!.ddFullName))
    }

    @Test
    func testError() async throws {
        throw TestError.test(Testing.Test.current!.ddFullName)
    }

    @Test
    func testErrorIgnore() async throws {
        throw TestError.test(Testing.Test.current!.ddFullName)
    }

    @Test(arguments: zip([1, 2, 3], ["1", "2", "3"]))
    func testParameterized(p1: Int, p2 second: String) async throws {
        #expect("\(p1)" == second)
    }

}

@Suite(.observerTester, .datadogTesting, .tags(.dd.nonretriable, .dd.tia.unskippable))
struct SwiftTestingTaggedSuiteTests {
    @Test
    func testRetriableTagObtainedFromSwiftTestingTags() async throws {
        let tags = try #require(Testing.Test.current).attachedTags
        #expect(tags.get(tag: .retriable) == false)
    }

    @Test
    func testTiaSkippableTagObtainedFromSwiftTestingTags() async throws {
        let tags = try #require(Testing.Test.current).attachedTags
        #expect(tags.get(tag: .tiaSkippable) == false)
    }

    @Test(.tags(.dd.retriable))
    func testRetriableTagOverridesSuiteNonretriableTag() async throws {
        let tags = try #require(Testing.Test.current).attachedTags
        #expect(tags.get(tag: .retriable) == true)
    }

    @Test(.tags(.dd.tia.skippable))
    func testSkippableTagOverridesSuiteUnskippableTag() async throws {
        let tags = try #require(Testing.Test.current).attachedTags
        #expect(tags.get(tag: .tiaSkippable) == true)
    }
}

@Test(.observerTester, .datadogTesting)
func testFuncRetryErrorShouldFail() async throws {
    throw SwiftTestingTraitTests.TestError.test(Testing.Test.current!.ddFullName)
}

@Test(.observerTester, .datadogTesting)
func testFuncRegistration() async throws {
    #expect(Testing.Test.current?.ddSuite == "[\(URL(string: #file)!.deletingPathExtension().lastPathComponent)]")
}

#if compiler(>=6.3)
@Test(.observerTester, .datadogTesting)
func zzzzFuncCancel() async throws {
    try Testing.Test.cancel(Comment(rawValue: Testing.Test.current!.ddFullName))
}
#endif

private extension Testing.Test {
    /// Suite-qualified test identifier (e.g. `"SwiftTestingTraitTests.testPass"`)
    /// used as the unique key in `ObserverTesterTrait`'s expected map and the
    /// payload carried by issues raised inside tests.
    var ddFullName: String { "\(ddSuite).\(ddName)" }
}


/// Verifies that `ddSuite` joins the full enclosing-type chain into a dotted
/// path (e.g. `"Outer.Inner"`) so nested `@Suite` types don't collide on the
/// outermost type name in the registry and function-lines lookup.
@Suite(.observerTester, .datadogTesting)
struct DDSuiteNamingTests {
    @Test func topLevelSuiteName() async throws {
        #expect(Testing.Test.current?.ddSuite == "DDSuiteNamingTests")
    }

    struct NestedSuite {
        @Test func nestedSuiteName() async throws {
            #expect(Testing.Test.current?.ddSuite == "DDSuiteNamingTests.NestedSuite")
        }

        struct DoublyNestedSuite {
            @Test func doublyNestedSuiteName() async throws {
                #expect(Testing.Test.current?.ddSuite == "DDSuiteNamingTests.NestedSuite.DoublyNestedSuite")
            }
        }
    }
}

/// Regression test for https://github.com/DataDog/dd-sdk-swift-testing/issues/257.
/// When both an outer and an inner `@Suite` carry `.datadogTesting`, Swift
/// Testing chains a separate trait instance for each annotation level around
/// the inner scope. Without dedupe each instance creates its own retry group
/// for the test, producing a second `runs` entry (which surfaced as a
/// duplicate test result in the Datadog UI). The trait scope provider must
/// short-circuit when an outer trait instance already provides scope for the
/// same suite / test / run.
@Suite(.observerTester, .datadogTesting)
struct DDNestedAnnotatedSuiteTests {
    @Suite(.observerTester, .datadogTesting)
    struct InnerAnnotated {
        @Test func nestedTraitTest() async throws {
            #expect(Testing.Test.current?.ddSuite == "DDNestedAnnotatedSuiteTests.InnerAnnotated")
        }
    }
}

private final class MockSwiftTestingObserver: SwiftTestingObserverType {
    func willStart(suite: borrowing SwiftTestingSuiteContext) async {}

    func willFinish(suite: borrowing SwiftTestingSuiteContext) async {}

    func didFinish(suite: borrowing SwiftTestingSuiteContext, active: borrowing SwiftTestingSuiteContext?) async {}

    func willStart(test: borrowing SwiftTestingTestContext) async {}

    func didFinish(test: borrowing SwiftTestingTestContext) async {}

    func runGroupConfiguration(test: borrowing SwiftTestingTestContext) async -> (feature: FeatureId?, configuration: RetryGroupConfiguration) {
        let name = test.info.name.lowercased()
        guard test.info.suite == "SwiftTestingTraitTests" else {
            return (nil, .retry(.init(skipStatus: .init(canBeSkipped: false, markedUnskippable: false))))
        }
        if name.contains("skip") {
            return ("skip_test", .skip(reason: "skip_test",
                                       configuration: .init(skipStatus: .init(canBeSkipped: true,
                                                                              markedUnskippable: false))))
        }
        if name.contains("ignore") {
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

/// Serialises the post-check section across parallel @Suite types that share
/// `ObserverTesterTrait`. Swift Testing runs `@Suite` types in parallel by
/// default, so two suites can reach the trait's post-checks concurrently.
/// `Mocks.SessionManager.stop()` nils both `SessionManager._session` and
/// `DatadogSwiftTestingTrait.sharedSuiteProvider`, so a naive race lets one
/// suite tear down state while the other is still reading it.
///
/// - `session(for:)` captures the underlying `Mocks.Session` and stashes the
///   first reference seen. Later callers that race past `stop()` get the
///   stashed reference (the `Mocks.Session` itself stays alive — only the
///   manager's pointer is cleared).
/// - `stopOnce(via:)` ensures `session.stop()` runs at most once, no matter
///   how many sibling suites think the module has ended.
private actor PostCheckGate {
    private var stashed: Mocks.Session?
    private var didStop: Bool = false

    func session(for provider: SwiftTestingSuiteProvider) async -> Mocks.Session? {
        // `provider.session.session` throws when the SessionManager has been
        // stopped (it returns nil internally and the protocol default rethrows
        // it as an error). Treat that as "fall back to the stashed reference".
        if let live = try? await provider.session.session as? Mocks.Session {
            if stashed == nil { stashed = live }
            return live
        }
        return stashed
    }

    func stopOnce(via provider: SwiftTestingSuiteProvider) async {
        guard !didStop else { return }
        didStop = true
        await provider.session.stop()
    }
}

private struct ObserverTesterTrait: SuiteTrait, TestTrait, TestScoping {
    let isRecursive: Bool = false

    private static let gate = PostCheckGate()

    /// Lazy setup of the shared suite provider. Called from both `prepare(for:)`
    /// and `provideScope(for:testCase:performing:)`. The latter matters when
    /// XCTest relaunches the bundle after a crash: Swift Testing skips
    /// `prepare(for:)` for suites whose tests all completed in the previous
    /// launch but still invokes the suite-level `provideScope`, so without
    /// this guard `DatadogSwiftTestingTrait.sharedSuiteProvider` would be nil
    /// and the trait's `#require` would crash the test runner with
    /// "Recording issues for suites is not supported".
    private static func ensureSuiteProvider() {
        guard DatadogSwiftTestingTrait.sharedSuiteProvider == nil else { return }
        let session = Mocks.SessionManager(provider: Mocks.Session.Provider(),
                                           config: .init(activeFeatures: [],
                                                         env: DDTestMonitor.env,
                                                         config: DDTestMonitor.config,
                                                         clock: DateClock(),
                                                         crash: nil,
                                                         command: nil,
                                                         log: Mocks.CatchLogger()),
                                           observer: SessionAndModuleObserver())
        DatadogSwiftTestingTrait.sharedSuiteProvider = SwiftTestingSuiteProvider(session: session,
                                                                                 observer: MockSwiftTestingObserver())
    }

    func prepare(for test: Testing.Test) async throws {
        Self.ensureSuiteProvider()
    }

    func provideScope(for test: Testing.Test, testCase: Testing.Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        Self.ensureSuiteProvider()
        // Capture the shared provider into a local up-front: a sibling suite's
        // `session.stop()` runs `SessionAndModuleObserver.didFinish(session:)`
        // which nils `DatadogSwiftTestingTrait.sharedSuiteProvider`. Without
        // this capture the post-checks below would race the sibling and read
        // `nil`, triggering Swift Testing's fatal "Recording issues for suites
        // is not supported".
        let suiteProvider = try #require(DatadogSwiftTestingTrait.sharedSuiteProvider as? SwiftTestingSuiteProvider)
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
        
        let tests = await suiteProvider.registry.registeredTests
        let suite = try #require(tests[test.ddModule]?[test.ddSuite])
        // Route session capture through the gate so a sibling that has already
        // called `stop()` (which nils `SessionManager._session`) doesn't
        // starve us — the gate hands back the stashed reference instead.
        // The `await` is pulled out of `#require` because Swift Testing's
        // macro expansion does not reliably re-introduce `await` inside the
        // synthesized closure on older toolchains (tvOS 26.2 / Testing 1501).
        let resolvedSession = await Self.gate.session(for: suiteProvider)
        let session = try #require(resolvedSession)
        let statuses = try #require(session.modules[test.ddModule]?.suites[test.ddSuite])

        // check is module ended and if ended - stop the test session. The gate
        // ensures `stop()` runs exactly once across all parallel sibling suites.
        if session.modules.first?.value.duration ?? 0 > 0 {
            await Self.gate.stopOnce(via: suiteProvider)
        }

        let errors = issues.value
        let cancels = cancelled.value
        
        // Keyed by the suite-qualified test name (`"<ddSuite>.<ddName>"`) so
        // tests that share a function name across nested suites don't collide.
        let expected: [String: (status: [TestStatus], errors: Int?, cancelled: Bool?)] = [
            "SwiftTestingTraitTests.scopingTraitIsApplied": ([.pass], nil, nil),
            "SwiftTestingTraitTests.testSkip": ([.skip], nil, nil),
            "SwiftTestingTraitTests.testRetryIgnore": (Array(repeating: .fail, count: 5), nil, nil),
            "SwiftTestingTraitTests.testRetryShouldFail": (Array(repeating: .fail, count: 5), 1, nil),
            "SwiftTestingTraitTests.testRetryErrorIgnore": (Array(repeating: .fail, count: 5), nil, nil),
            "SwiftTestingTraitTests.testRetryErrorShouldFail": (Array(repeating: .fail, count: 5), 1, nil),
            "SwiftTestingTraitTests.testPass": ([.pass], nil, nil),
            "SwiftTestingTraitTests.testShouldFail": ([.fail], 1, nil),
            "SwiftTestingTraitTests.testError": ([.fail], 1, nil),
            "SwiftTestingTraitTests.testErrorIgnore": ([.fail], nil, nil),
            "SwiftTestingTraitTests.testParameterized(p1:p2:)": (Array(repeating: .pass, count: 3), nil, nil),
            "SwiftTestingTaggedSuiteTests.testRetriableTagObtainedFromSwiftTestingTags": ([.pass], nil, nil),
            "SwiftTestingTaggedSuiteTests.testTiaSkippableTagObtainedFromSwiftTestingTags": ([.pass], nil, nil),
            "SwiftTestingTaggedSuiteTests.testRetriableTagOverridesSuiteNonretriableTag": ([.pass], nil, nil),
            "SwiftTestingTaggedSuiteTests.testSkippableTagOverridesSuiteUnskippableTag": ([.pass], nil, nil),
            "DDSuiteNamingTests.topLevelSuiteName": ([.pass], nil, nil),
            "DDSuiteNamingTests.NestedSuite.nestedSuiteName": ([.pass], nil, nil),
            "DDSuiteNamingTests.NestedSuite.DoublyNestedSuite.doublyNestedSuiteName": ([.pass], nil, nil),
            "DDNestedAnnotatedSuiteTests.InnerAnnotated.nestedTraitTest": ([.pass], nil, nil),
            "[SwiftTestingTraitTests].testFuncRetryErrorShouldFail": (Array(repeating: .fail, count: 5), 1, nil),
            "[SwiftTestingTraitTests].testFuncRegistration": ([.pass], nil, nil),
            "[SwiftTestingTraitTests].zzzzFuncCancel": ([.skip], nil, true)
        ]

        // If we have a suite we should check for all tests it owns.
        // If we have a function we only check that function; the framework
        // invokes provideScope separately for each test.
        let suiteName = test.ddSuite
        let testNames: [String] = test.isSuite ? Array(suite) : [test.ddName]
        for testName in testNames {
            let fullName = "\(suiteName).\(testName)"
            let expect = try #require(expected[fullName], "missing expectation for \(fullName)")
            let status = try #require(statuses[testName]).runs.map { $0.status }
            #expect(status == expect.status)
            #expect(errors[fullName] == expect.errors)
            #expect(cancels[fullName] == expect.cancelled)
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
                [(name: "p1", value: "1", type: "Swift.Int"), (name: "p2 second", value:"\"1\"", type:"Swift.String")],
                [(name: "p1", value: "2", type: "Swift.Int"), (name: "p2 second", value:"\"2\"", type:"Swift.String")],
                [(name: "p1", value: "3", type: "Swift.Int"), (name: "p2 second", value:"\"3\"", type:"Swift.String")]
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
