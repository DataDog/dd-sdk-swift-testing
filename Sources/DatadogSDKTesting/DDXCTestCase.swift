/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import XCTest

protocol DDXCTestSuppressedFailureRun: AnyObject {
    var ddHasFailed: Bool { get }
}

final class DDXCTestCaseRetryRun: XCTestCaseRun, DDXCTestSuppressedFailureRun {
    private var _suppressFailure: Bool = false
    
    private(set) var suppressedFailures: [XCTIssue] = []
    
    var ddHasFailed: Bool {
        guard startDate != nil && stopDate != nil else {
            return false
        }
        return ddTotalFailureCount > 0
    }
    
    var ddTotalFailureCount: Int { totalFailureCount + suppressedFailures.count }
    
    var canFail: Bool { ddTotalFailureCount > 0 }
    
    func suppressFailure() {
        _suppressFailure = true
    }
    
    func recordSuppressedFailures() {
        let failures = suppressedFailures
        suppressedFailures = []
        for failure in failures {
            super.record(failure)
        }
    }
    
    override func stop() {
        NotificationCenter.test.postTestCaseRetryWillFinish(test as! XCTestCase)
        super.stop()
    }
    
    override func record(_ issue: XCTIssue) {
        NotificationCenter.test.postTestCaseRetry(test as! XCTestCase, willRecord: issue)
        if _suppressFailure {
            suppressedFailures.append(issue)
            _suppressFailure = false
        } else {
            super.record(issue)
        }
    }
}

final class DDXCTestRetryGroupRun: XCTestRun, DDXCTestSuppressedFailureRun {
    private(set) var testRuns: [DDXCTestCaseRetryRun] = []
    var group: DDXCTestRetryGroup { test as! DDXCTestRetryGroup }
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
        NotificationCenter.test.postTestRetryGroupWillStart(group)
        super.start()
    }
    
    override func stop() {
        super.stop()
        NotificationCenter.test.postTestRetryGroupDidFinish(group)
    }
    
    func addTestRun(_ run: DDXCTestCaseRetryRun) {
        testRuns.append(run)
    }
}

final class DDXCTestRetryGroup: XCTest {
    private(set) var currentTest: XCTestCase?
    
    override var name: String { _name }
    override var testCaseCount: Int { testRun?.executionCount ?? 1 }
    override var testRunClass: AnyClass? { DDXCTestRetryGroupRun.self }
    let testClass: XCTestCase.Type
    
    private(set) var retryReason: String?
    
    var groupRun: DDXCTestRetryGroupRun? { testRun.map { $0 as! DDXCTestRetryGroupRun } }
    
    let testId: (suite: String, test: String)
    
    private let _name: String
    private let _testMethod: Selector
    private var _skipReason: String?
    private var _nextTest: XCTestCase?
    private var _nextRetryReason: String?
    
    init(for test: XCTestCase) {
        self.currentTest = test
        self.testId = test.testId
        self._skipReason = nil
        self._nextTest = nil
        self.retryReason = nil
        self._nextRetryReason = nil
        self._name = test.name
        self.testClass = type(of: test)
        self._testMethod = test.invocation!.selector
        super.init()
    }
    
    func skip(reason: String) {
        _skipReason = reason
        _nextTest = nil
        _nextRetryReason = nil
        retryReason = nil
    }
    
    func retry(reason: String) {
        _nextTest = testClass.init(selector: _testMethod)
        _nextRetryReason = reason
        _skipReason = nil
    }
    
    override func perform(_ run: XCTestRun) {
        guard let testRun = run as? DDXCTestRetryGroupRun else {
            fatalError("Wrong XCTestRun class. Expected DDXCTestRetryGroupRun")
        }
        testRun.start()
        while let test = currentTest {
            let testCaseRun = DDXCTestCaseRetryRun(test: test)
            test.setValue(testCaseRun, forKey: "testRun")
            testRun.addTestRun(testCaseRun)
            if let reason = _skipReason {
                _skipReason = nil
                DDXCSkippedTestCase().set(reason: reason).perform(testCaseRun)
            } else {
                test.perform(testCaseRun)
            }
            currentTest = _nextTest
            retryReason = _nextRetryReason
            _nextTest = nil
            _nextRetryReason = nil
        }
        testRun.stop()
    }
    
    @objc var _requiredTestRunBaseClass: AnyClass? { XCTestRun.self }
    
    override var description: String { "\(name)[\(testRun?.executionCount ?? 0)]" }
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
        private let checker: (DDXCTestRetryGroupRun) -> Bool
        
        required init(checker: @escaping (DDXCTestRetryGroupRun) -> Bool) {
            self.checker = checker
        }
        
        func execute(for group: DDXCTestRetryGroupRun) -> Bool {
            checker(group)
        }
        
        static func custom(_ checker: @escaping (DDXCTestRetryGroupRun) -> Bool) -> Self {
            Self(checker: checker)
        }
    }
    
    final class SuccessStrategy: GroupStrategy {
        static var allSucceeded: Self { .custom { $0.ddTotalFailureCount == 0 } }
        static var atLeastOneSucceeded: Self { .custom { $0.failedExecutionCount < $0.executionCount } }
        static var atMostOneFailed: Self { .custom { $0.failedExecutionCount <= 1 } }
    }
    
    final class SkipStrategy: GroupStrategy {
        static var allSkipped: Self { .custom { $0.skippedExecutionCount == $0.executionCount } }
        static var atLeastOneSkipped: Self { .custom { $0.skippedExecutionCount > 0  } }
    }
}

extension Notification.Name {
    static var testRetryGroupWillStart: Self { .init("DDTestRetryGroupWillStart") }
    static var testRetryGroupDidFinish: Self { .init("DDTestRetryGroupDidFinish") }
    static var testCaseFromRetryGroupWillRecordIssue: Self { .init("DDTestCaseFromRetryGroupWillRecordIssue") }
    static var testCaseFromRetryGroupWillFinish: Self { .init("DDTestCaseFromRetryGroupWillFinish") }
}

extension NotificationCenter {
    static let test: NotificationCenter = NotificationCenter()
    
    func onTestRetryGroupWillStart(_ observer: @escaping (DDXCTestRetryGroup) -> Void) -> NSObjectProtocol {
        addObserver(forName: .testRetryGroupWillStart, object: nil, queue: nil) { notification in
            observer(notification.object as! DDXCTestRetryGroup)
        }
    }
    
    func onTestRetryGroupDidFinish(_ observer: @escaping (DDXCTestRetryGroup) -> Void) -> NSObjectProtocol {
        addObserver(forName: .testRetryGroupDidFinish, object: nil, queue: nil) { notification in
            observer(notification.object as! DDXCTestRetryGroup)
        }
    }
    
    func onTestCaseRetryWillRecordIssue(_ observer: @escaping (XCTestCase, XCTIssue) -> Void) -> NSObjectProtocol {
        addObserver(forName: .testCaseFromRetryGroupWillRecordIssue, object: nil, queue: nil) { notification in
            observer(notification.object as! XCTestCase, notification.userInfo!["issue"] as! XCTIssue)
        }
    }
    
    func onTestCaseRetryWillFinish(_ observer: @escaping (XCTestCase) -> Void) -> NSObjectProtocol {
        addObserver(forName: .testCaseFromRetryGroupWillFinish, object: nil, queue: nil) { notification in
            observer(notification.object as! XCTestCase)
        }
    }
    
    func postTestRetryGroupWillStart(_ group: DDXCTestRetryGroup) {
        post(name: .testRetryGroupWillStart, object: group)
    }
    
    func postTestRetryGroupDidFinish(_ group: DDXCTestRetryGroup) {
        post(name: .testRetryGroupDidFinish, object: group)
    }
    
    func postTestCaseRetry(_ testCase: XCTestCase, willRecord issue: XCTIssue) {
        post(name: .testCaseFromRetryGroupWillRecordIssue, object: testCase, userInfo: ["issue": issue])
    }
    
    func postTestCaseRetryWillFinish(_ testCase: XCTestCase) {
        post(name: .testCaseFromRetryGroupWillFinish, object: testCase)
    }
}

extension RetryGroupSuccessStrategy {
    var xcTest: DDXCTestRetryGroupRun.SuccessStrategy {
        switch self {
        case .allSucceeded: return .allSucceeded
        case .atLeastOneSucceeded: return .atLeastOneSucceeded
        case .atMostOneFailed: return .atMostOneFailed
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
