/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import XCTest

protocol DDXCTestSuppressedFailureRun: AnyObject {
    var ddHasFailed: Bool { get }
}

protocol DDXCTestRetryDelegate: AnyObject {
    func testRetryGroupWillStart(_ group: any DDXCTestRetryGroupType)
    func testRetryGroupDidFinish(_ group: any DDXCTestRetryGroupType)
    func testCaseRetryWillFinish(_ testCase: XCTestCase)
    func testCaseRetry(_ testCase: XCTestCase, willRecord issue: XCTIssue)
    func testCaseRetryDidFinish(_ testCase: XCTestCase)
}

protocol DDXCTestRetryGroupType: AnyObject {
    var name: String { get }
    var currentTest: XCTestCase? { get }
    var groupRun: (any DDXCTestRetryGroupRunType)? { get }
    var testId: (suite: String, test: String) { get }
    var context: DDXCTestObserver.GroupContext! { get set }
    var observer: any DDXCTestRetryDelegate { get }
    func skip(reason: String)
    func retry()
}

protocol DDXCTestCaseRetryRunType: DDXCTestSuppressedFailureRun {
    var hasBeenSkipped: Bool { get }
    var startDate: Date? { get }
    var ddTest: any TestRun { get }
    var group: any DDXCTestRetryGroupType { get }
    var ddHasFailed: Bool { get }
    var ddTotalFailureCount: Int { get }
    var skipReason: String? { get }
    var suppressedFailures: [XCTIssue] { get }
    
    func suppressFailure()
    func recordSuppressedFailures()
#if canImport(ObjectiveC)
    func recordSuppressedFailuresAsExpected(reason: String)
#endif // canImport(ObjectiveC)
}

protocol DDXCTestRetryGroupRunType: DDXCTestSuppressedFailureRun {
    var group: any DDXCTestRetryGroupType { get }
    var successStrategy: DDXCTestRetryGroupRun.SuccessStrategy { get set }
    var skipStrategy: DDXCTestRetryGroupRun.SkipStrategy { get set }
    
    var ddTotalFailureCount: Int { get }
    var failedExecutionCount: Int { get }
    var executionCount: Int { get }
    var skippedExecutionCount: Int { get }
}

extension DDXCTestCaseRetryRunType {
    var canFail: Bool { ddTotalFailureCount > 0 }
    var context: DDXCTestObserver.GroupContext {
        get { group.context }
        set { group.context = newValue }
    }
}

final class DDXCTestCaseRetryRun: XCTestCaseRun, DDXCTestCaseRetryRunType {
    private var _suppressFailure: Bool = false
    
    private(set) var suppressedFailures: [XCTIssue] = []
    private(set) var expectedFailuresCount: Int = 0
    
    let ddTest: any TestRun
    let group: any DDXCTestRetryGroupType
    
    init(xcTest: XCTest, test: any TestRun, group: any DDXCTestRetryGroupType) {
        self.ddTest = test
        self.group = group
        super.init(test: xcTest)
    }
    
    var ddHasFailed: Bool {
        guard startDate != nil && stopDate != nil else {
            return false
        }
        return ddTotalFailureCount > 0
    }
    
    var ddTotalFailureCount: Int {
        totalFailureCount + expectedFailuresCount + suppressedFailures.count
    }
    
    private(set) var skipReason: String? = nil
    
    func suppressFailure() {
        _suppressFailure = true
    }
    
    func recordSuppressedFailures() {
        let failures = suppressedFailures
        // we don't have to preserve count because they will be added to totalFailureCount
        suppressedFailures = []
        for failure in failures {
            super.record(failure)
        }
    }
    
#if canImport(ObjectiveC)
    func recordSuppressedFailuresAsExpected(reason: String) {
        let failures = suppressedFailures
        // we have to preserve their count, because they will not be attached to the test run
        expectedFailuresCount += failures.count
        suppressedFailures = []
        let selector = "alloc"
        for failure in failures {
            if let expected = XCTExpectedFailure.self.perform(Selector(selector)).takeUnretainedValue() as? XCTExpectedFailure {
                if let expected = expected.perform(Selector(("initWithFailureReason:issue:")), with: reason, with: failure)
                                          .takeRetainedValue() as? XCTExpectedFailure
                {
                    self.perform(Selector(("recordExpectedFailure:")), with: expected)
                }
            }
        }
    }
#endif
    
    override func stop() {
        group.observer.testCaseRetryWillFinish(test as! XCTestCase)
        super.stop()
    }

    override func record(_ issue: XCTIssue) {
        group.observer.testCaseRetry(test as! XCTestCase, willRecord: issue)
        if _suppressFailure {
            suppressedFailures.append(issue)
            _suppressFailure = false
        } else {
            super.record(issue)
        }
    }
    
#if canImport(ObjectiveC)
    private typealias RecordSkip = @convention(c) (AnyObject, Selector, String, XCTSourceCodeContext?) -> Void
    
    // it's a hack to get skip messages
    @objc(recordSkipWithDescription:sourceCodeContext:)
    func recordSkip(description: String, sourceCodeContext context: XCTSourceCodeContext?) {
        skipReason = description
        // we cant call super here because we don't have an override
        // so we will call super method with ObjC runtime API
        let selector = #selector(self.recordSkip(description:sourceCodeContext:))
        if let parent = class_getMethodImplementation(self.superclass, selector) {
            let recordSkip = unsafeBitCast(parent, to: RecordSkip.self)
            recordSkip(self, selector, description, context)
        }
    }
#endif // canImport(ObjectiveC)
}

final class DDXCTestRetryGroupRun: XCTestRun, DDXCTestRetryGroupRunType {
    private(set) var testRuns: [DDXCTestCaseRetryRun] = []
    var group: any DDXCTestRetryGroupType { test as! DDXCTestRetryGroupType }
    var successStrategy: SuccessStrategy = .allSucceeded
    var skipStrategy: SkipStrategy = .allSkipped
    
    override var totalDuration: TimeInterval {
        testRuns.reduce(TimeInterval(0.0)) { $0 + $1.totalDuration }
    }
    
    override var executionCount: Int {
        testRuns.reduce(0) { $0 + $1.executionCount }
    }
    
    override var skipCount: Int {
        testRuns.reduce(0) { $0 + $1.skipCount }
    }
    
    override var failureCount: Int {
        testRuns.reduce(0) { $0 + $1.failureCount }
    }
    
    override var unexpectedExceptionCount: Int {
        testRuns.reduce(0) { $0 + $1.unexpectedExceptionCount }
    }
    
    override var hasSucceeded: Bool {
        guard startDate != nil && stopDate != nil else {
            return false
        }
        return successStrategy.execute(for: self)
    }
    
    override var hasBeenSkipped: Bool {
        guard startDate != nil && stopDate != nil else {
            return false
        }
        return skipStrategy.execute(for: self)
    }
    
    var ddHasFailed: Bool {
        guard startDate != nil && stopDate != nil else {
            return false
        }
        return !hasSucceeded
    }
    
    var ddTotalFailureCount: Int {
        testRuns.reduce(0) { $0 + $1.ddTotalFailureCount }
    }
    
    var canFail: Bool { !successStrategy.execute(for: self) }
    
    var failedExecutionCount: Int {
        testRuns.reduce(0) { $0 + ($1.ddHasFailed ? $1.executionCount : 0) }
    }
    
    var skippedExecutionCount: Int {
        testRuns.reduce(0) { $0 + ($1.hasBeenSkipped ? $1.executionCount : 0) }
    }
    
    override func start() {
        group.observer.testRetryGroupWillStart(group)
        super.start()
    }

    override func stop() {
        super.stop()
        group.observer.testRetryGroupDidFinish(group)
    }
    
    func addTestRun(_ run: DDXCTestCaseRetryRun) {
        testRuns.append(run)
    }
}

final class DDXCTestRetryGroup: XCTest, DDXCTestRetryGroupType {
    private(set) var currentTest: XCTestCase?

    override var name: String { _name }
    override var testCaseCount: Int { testRun?.executionCount ?? 1 }
    override var testRunClass: AnyClass? { DDXCTestRetryGroupRun.self }
    let testClass: XCTestCase.Type

    var groupRun: (any DDXCTestRetryGroupRunType)? { testRun.map { $0 as! DDXCTestRetryGroupRunType } }

    let testId: (suite: String, test: String)
    var context: DDXCTestObserver.GroupContext!
    let observer: any DDXCTestRetryDelegate

    private let _name: String
    private let _testMethod: Selector
    private var _skipReason: String?
    private var _nextTest: XCTestCase?

    init(for test: XCTestCase, observer: any DDXCTestRetryDelegate) {
        self.currentTest = test
        self.testId = test.testId
        self._skipReason = nil
        self._nextTest = nil
        self._name = test.name
        self.testClass = type(of: test)
        self._testMethod = test.invocation!.selector
        self.observer = observer
        super.init()
    }
    
    func skip(reason: String) {
        _skipReason = reason
        _nextTest = nil
    }
    
    func retry() {
        _nextTest = testClass.init(selector: _testMethod)
        _skipReason = nil
    }
    
    override func perform(_ run: XCTestRun) {
        guard let groupRun = run as? DDXCTestRetryGroupRun else {
            fatalError("Wrong XCTestRun class. Expected DDXCTestRetryGroupRun")
        }
        groupRun.start()
        while let xcTest = currentTest {
            context.suite.withActiveTest(named: xcTest.testId.test) { test in
                let xcTestRun = DDXCTestCaseRetryRun(xcTest: xcTest, test: test, group: self)
                xcTest.setValue(xcTestRun, forKey: "testRun")
                groupRun.addTestRun(xcTestRun)
                
                if let reason = _skipReason {
                    _skipReason = nil
                    DDXCSkippedTestCase().set(reason: reason).perform(xcTestRun)
                } else {
                    xcTest.perform(xcTestRun)
                }
            }
            // Call didFinish callback
            observer.testCaseRetryDidFinish(xcTest)
            // setup next iteration
            currentTest = _nextTest
            _nextTest = nil
        }
        groupRun.stop()
    }
    
    override var description: String { "\(name)[\(testRun?.executionCount ?? 0)]" }
    
#if canImport(ObjectiveC)
    @objc var _requiredTestRunBaseClass: AnyClass? { XCTestRun.self }
#endif // canImport(ObjectiveC)
}

final class DDXCSkippedTestCase: XCTestCase {
    private var reason: String! = nil
    
    func set(reason: String) -> Self {
        self.reason = reason
        return self
    }
    
    override func setUpWithError() throws {
        self.continueAfterFailure = false
        throw XCTSkip(reason)
    }
}

extension DDXCTestRetryGroupRun {
    class GroupStrategy {
        private let checker: (DDXCTestRetryGroupRunType) -> Bool
        
        required init(checker: @escaping (DDXCTestRetryGroupRunType) -> Bool) {
            self.checker = checker
        }
        
        func execute(for group: DDXCTestRetryGroupRunType) -> Bool {
            checker(group)
        }
        
        static func custom(_ checker: @escaping (DDXCTestRetryGroupRunType) -> Bool) -> Self {
            Self(checker: checker)
        }
    }
    
    final class SuccessStrategy: GroupStrategy {
        static var allSucceeded: Self { .custom { $0.ddTotalFailureCount == 0 } }
        static var atLeastOneSucceeded: Self { .custom { $0.failedExecutionCount < $0.executionCount } }
        static var atMostOneFailed: Self { .custom { $0.failedExecutionCount <= 1 } }
        static var alwaysSucceeded: Self { .custom { _ in true } }
    }
    
    final class SkipStrategy: GroupStrategy {
        static var allSkipped: Self { .custom { $0.skippedExecutionCount == $0.executionCount } }
        static var atLeastOneSkipped: Self { .custom { $0.skippedExecutionCount > 0  } }
    }
}


extension RetryGroupSuccessStrategy {
    var xcTest: DDXCTestRetryGroupRun.SuccessStrategy {
        switch self {
        case .allSucceeded: return .allSucceeded
        case .atLeastOneSucceeded: return .atLeastOneSucceeded
        case .atMostOneFailed: return .atMostOneFailed
        case .alwaysSucceeded: return .alwaysSucceeded
        }
    }
}

extension RetryGroupSkipStrategy {
    var xcTest: DDXCTestRetryGroupRun.SkipStrategy {
        switch self {
        case .allSkipped: return .allSkipped
        case .atLeastOneSkipped: return .atLeastOneSkipped
        }
    }
}


protocol XCTestTag: TestTag {
    func parse(tags: borrowing TypeTags, test: String) -> Value?
}

// XCTest is synchronous so it's not synchronized
final class XCTestSuiteTags: Identifiable {
    typealias ID = ObjectIdentifier
    
    var id: ObjectIdentifier { ObjectIdentifier(_clazz) }
    
    private let _clazz: XCTestCase.Type
    private(set) lazy var tags: TypeTags? = _clazz.maybeTypeTags
    
    init(for clazz: XCTestCase.Type) {
        self._clazz = clazz
    }
    
    func tags(for test: String) -> XCTestTags {
        .init(suite: self, test: test)
    }
}

struct XCTestTags: TestTags {
    let suite: XCTestSuiteTags
    let test: String
        
    init(suite: XCTestSuiteTags, test: String) {
        self.suite = suite
        self.test = test
    }
    
    func get<T: TestTag>(tag: T) -> T.Value? {
        guard let tag = tag as? any XCTestTag else {
            return nil
        }
        guard let tags = suite.tags else {
            return nil
        }
        // have to cast because normal types work from macOS 13 only
        return tag.parse(tags: tags, test: test) as! T.Value?
    }
}
