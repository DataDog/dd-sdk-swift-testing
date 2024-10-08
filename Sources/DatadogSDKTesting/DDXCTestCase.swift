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
    var suppressFailure: Bool = false
    
    var ddHasFailed: Bool {
        guard startDate != nil && stopDate != nil else {
            return false
        }
        return totalSuppressedFailureCount > 0
    }
    
    var totalSuppressedFailureCount: Int { totalFailureCount + _suppressedFailures }
    
    private(set) var _suppressedFailures: Int = 0
    
    override func record(_ issue: XCTIssue) {
        NotificationCenter.test.postTestCaseRetry(test as! XCTestCase, willRecord: issue)
        if suppressFailure {
            _suppressedFailures += 1
            suppressFailure = false
        } else {
            super.record(issue)
        }
    }
}

final class DDXCTestRetryGroupRun: XCTestRun, DDXCTestSuppressedFailureRun {
    private(set) var testRuns: [DDXCTestCaseRetryRun] = []
    var group: DDXCTestRetryGroup { test as! DDXCTestRetryGroup }
    var successStrategy: SuccessStragegy = .allSucceeded
    
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
        return successStrategy.isSucceded(run: self)
    }
    
    override var hasBeenSkipped: Bool {
        guard startDate != nil && stopDate != nil else {
            return false
        }
        return skippedExecutions != 0
    }
    
    var ddHasFailed: Bool {
        guard startDate != nil && stopDate != nil else {
            return false
        }
        return !hasSucceeded
    }
    
    var totalSuppressedFailureCount: Int {
        testRuns.reduce(0) { $0 + $1.totalSuppressedFailureCount }
    }
    
    var failedExecutions: Int {
        testRuns.reduce(0) { $0 + $1.totalSuppressedFailureCount == 0 ? 0 : 1 }
    }
    
    var skippedExecutions: Int {
        testRuns.reduce(0) { $0 + $1.skipCount == 0 ? 0 : 1 }
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
    
    var groupRun: DDXCTestRetryGroupRun? { testRun.map { $0 as! DDXCTestRetryGroupRun } }
    
    let testId: (suite: String, test: String)
    
    private let _name: String
    private let _testMethod: Selector
    private var _skipReason: String?
    private var _nextTest: XCTestCase?
    
    init(for test: XCTestCase) {
        self.currentTest = test
        self.testId = test.testId
        self._skipReason = nil
        self._nextTest = nil
        self._name = test.name
        self.testClass = type(of: test)
        self._testMethod = test.invocation!.selector
        super.init()
    }
    
    func skip(reason: String) {
        _skipReason = reason
    }
    
    func retry() {
        _nextTest = testClass.init(selector: _testMethod)
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
            if let reason = _skipReason {
                _skipReason = nil
                DDXCSkippedTestCase().set(reason: reason).perform(testCaseRun)
            } else {
                test.perform(testCaseRun)
            }
            testRun.addTestRun(testCaseRun)
            currentTest = _nextTest
            _nextTest = nil
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
    struct SuccessStragegy {
        private let checker: (DDXCTestRetryGroupRun) -> Bool
        
        func isSucceded(run: DDXCTestRetryGroupRun) -> Bool {
            checker(run)
        }
        
        static func custom(_ checker: @escaping (DDXCTestRetryGroupRun) -> Bool) -> Self {
            Self(checker: checker)
        }
        
        static var allSucceeded: Self { .custom { $0.failedExecutions == 0 } }
        static var atLeastOneSucceeded: Self { .custom { $0.failedExecutions < $0.executionCount } }
        static var atMostOneFailed: Self { .custom { $0.failedExecutions <= 1 } }
    }
}

extension Notification.Name {
    static var testRetryGroupWillStart: Self { .init("DDTestRetryGroupWillStart") }
    static var testRetryGroupDidFinish: Self { .init("DDTestRetryGroupDidFinish") }
    static var testCaseFromRetryGroupWillRecordIssue: Self { .init("DDTestCaseFromRetryGroupWillRecordIssue") }
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
    
    func postTestRetryGroupWillStart(_ group: DDXCTestRetryGroup) {
        post(name: .testRetryGroupWillStart, object: group)
    }
    
    func postTestRetryGroupDidFinish(_ group: DDXCTestRetryGroup) {
        post(name: .testRetryGroupDidFinish, object: group)
    }
    
    func postTestCaseRetry(_ testCase: XCTestCase, willRecord issue: XCTIssue) {
        post(name: .testCaseFromRetryGroupWillRecordIssue, object: testCase, userInfo: ["issue": issue])
    }
}