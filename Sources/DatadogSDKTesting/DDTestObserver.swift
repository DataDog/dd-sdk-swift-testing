/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import EventsExporter
@_implementationOnly import XCTest

class DDTestObserver: NSObject, XCTestObservation {
    private(set) var state: State
    private var observers: [NSObjectProtocol]

    override init() {
        XCUIApplication.swizzleMethods
        state = .none
        observers = []
        super.init()
    }
    
    func start() {
        XCTestObservationCenter.shared.addTestObserver(self)
        observers.append(NotificationCenter.test.onTestRetryGroupWillStart { [weak self] group in
            self?.testRetryGroupWillStart(group)
        })
        observers.append(NotificationCenter.test.onTestRetryGroupDidFinish { [weak self] group in
            self?.testRetryGroupDidFinish(group)
        })
        observers.append(NotificationCenter.test.onTestCaseRetryWillFinish { [weak self] tc in
            self?.testCaseRetryWillFinish(tc)
        })
        observers.append(NotificationCenter.test.onTestCaseRetryWillRecordIssue { [weak self] tc, issue in
            self?.testCaseRetry(tc, willRecord: issue)
        })
    }
    
    func stop() {
        observers.forEach { NotificationCenter.test.removeObserver($0) }
        observers.removeAll()
        XCTestObservationCenter.shared.removeTestObserver(self)
        DDTestMonitor.removeTestMonitor()
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        guard case .none = state else {
            Log.print("testBundleWillStart: Bad observer state: \(state), expected: .none")
            return
        }
        let bundleName = testBundle.name
        Log.debug("testBundleWillStart: \(bundleName)")
        let module = DDTestModule.start(bundleName: bundleName)
        module.testFramework = "XCTest"
        state = .module(module)
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        guard case .module(let module) = state else {
            Log.print("testBundleDidFinish: Bad observer state: \(state), expected: .module")
            return
        }
        guard module.bundleName == testBundle.name else {
            Log.print("testBundleDidFinish: Bad module: \(testBundle.name), expected: \(module.bundleName)")
            state = .none
            return
        }
        /// We need to wait for all the traces to be written to the backend before exiting
        module.end()
        state = .none
        Log.debug("testBundleDidFinish: \(module.bundleName)")
    }

    func testSuiteWillStart(_ testSuite: XCTestSuite) {
        let module: DDTestModule
        let parent: ContainerSuite?
        
        switch state {
        case .module(let mod):
            module = mod
            parent = nil
        case .container(suite: let cont, inside: let mod):
            module = mod
            parent = cont
        default:
            Log.print("testSuiteWillStart: Bad observer state: \(state), expected: .module or .container")
            return
        }
        
        if module.configError {
            Log.print("testSuiteWillStart: Failed, module config error")
            testSuite.testRun?.stop()
            exit(1)
        }

        guard let tests = testSuite.tests as? [XCTestCase] else {
            Log.debug("testSuiteWillStart: container \(testSuite.name)")
            state = .container(suite: ContainerSuite(suite: testSuite, parent: parent), inside: module)
            return
        }

        Log.measure(name: "waiting for test optimization to be started") {
            DDTestMonitor.instance?.ensureTestOptimizationStarted()
        }
        
        let wrappedTests = tests.map { DDXCTestRetryGroup(for: $0) }
        testSuite.setValue(wrappedTests, forKey: "_mutableTests")
        
        module.addExpectedTests(count: UInt(wrappedTests.count))
        
        let retries = DDTestMonitor.instance.flatMap { monitor in
            monitor.failedTestRetriesCount > 0
                ? (test: monitor.failedTestRetriesCount,
                   total: monitor.failedTestRetriesTotalCount)
                : nil
        }
        
        state = SuiteContext(
            parent: parent,
            skippableTests: DDTestMonitor.instance?.itr?.skippableTests,
            efd: DDTestMonitor.instance?.efd,
            retries: retries
        ).new(suite: testSuite, in: module)
        Log.debug("testSuiteWillStart: \(testSuite.name)")
    }

    func testSuiteDidFinish(_ testSuite: XCTestSuite) {
        switch state {
        case .container(suite: let suite, inside: let module):
            guard suite.suite.name == testSuite.name else {
                Log.print("testSuiteDidFinish: Bad suite: \(testSuite.name), expected: \(suite.suite.name)")
                return
            }
            state = suite.parent == nil ? .module(module) : .container(suite: suite.parent!, inside: module)
            Log.debug("testSuiteDidFinish: container \(testSuite.name)")
        case .suite(suite: let suite, context: let context):
            guard suite.name == testSuite.name else {
                Log.print("testSuiteDidFinish: Bad suite: \(testSuite.name), expected: \(suite.name)")
                return
            }
            suite.end()
            state = context.back(from: suite)
            Log.debug("testSuiteDidFinish: \(testSuite.name)")
        default:
            Log.print("testSuiteDidFinish: Bad observer state: \(state), expected: .suite or .container")
        }
    }
    
    func testRetryGroupWillStart(_ group: DDXCTestRetryGroup) {
        guard case .suite(suite: let suite, context: let context) = state else {
            Log.print("testRetryGroupWillStart: Bad observer state: \(state), expected: .suite")
            return
        }
        group.groupRun?.successStrategy = .atLeastOneSucceeded
        let itr = context.itr(for: group)
        if itr.markedUnskippable { suite.unskippable = true }
        if itr.skipped { group.skip(reason: "ITR") }
        state = context.new(group: group, in: suite, itr: itr)
        Log.debug("testRetryGroupWillStart: \(group.name)")
    }
    
    func testRetryGroupDidFinish(_ group: DDXCTestRetryGroup) {
        guard case .group(group: let sgroup, context: let context) = state else {
            Log.print("testRetryGroupDidFinish: Bad observer state: \(state), expected: .group")
            return
        }
        guard group.name == sgroup.name else {
            Log.print("Bad group: \(group), expected: \(sgroup)")
            return
        }
        state = context.back()
        Log.debug("testRetryGroupDidFinish: \(group.name), " +
                  "executions: \(group.groupRun?.executionCount ?? 0), " +
                  "failed: \(group.groupRun?.failedExecutionCount ?? 0)")
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        guard case .group(group: let group, context: let context) = state else {
            Log.print("testCaseWillStart: Bad observer state: \(state), expected: .group")
            return
        }
        let test = context.suite.testStart(name: testCase.testId.test, itr: context.itr)
        let isRerun = group.groupRun?.executionCount ?? 0 > 0
        if test.module.checkEfdStatus(for: test, efd: context.efd) {
            test.setTag(key: DDEfdTags.testIsNew, value: "true")
            if !isRerun { test.module.incrementNewTests() }
        }
        if isRerun {
            test.setTag(key: DDEfdTags.testIsRetry, value: "true")
        }
        state = context.new(test: test, in: group)
        Log.debug("testCaseWillStart: \(testCase.name)")
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        guard case .test(test: let test, group: let group, context: let context) = state else {
            Log.print("testCaseDidFinish: Bad observer state: \(state), expected: .test")
            return
        }
        guard testCase.name.contains(test.name) else {
            Log.print("Bad test: \(testCase), expected: \(test.name)")
            return
        }
        test.addBenchmarkTagsIfNeeded(from: testCase)
        test.end(status: testCase.testRun?.status ?? .fail)
        state = context.back(group: group)
        Log.debug("testCaseDidFinish: \(testCase.name)")
    }
    
    func testCaseRetryWillFinish(_ testCase: XCTestCase) {
        guard case .test(test: let test, group: let group, context: let context) = state else {
            Log.print("testCaseRetryWillFinish: Bad observer state: \(state), expected: .test")
            return
        }
        guard testCase.name.contains(test.name) else {
            Log.print("testCaseRetryWillFinish: Bad test: \(testCase), expected: \(test.name)")
            return
        }
        Log.debug("testCaseRetryWillFinish: \(testCase)")
        guard let testRun = testCase.testRun as? DDXCTestCaseRetryRun else {
            Log.print("Unknown test run type: \(type(of: testCase.testRun)) for \(testCase)")
            return
        }
        guard let groupRun = group.groupRun else {
            Log.print("Bad observer state. Group run in nil")
            testRun.recordSuppressedFailures()
            return
        }
        
        if test.module.checkEfdStatus(for: test, efd: context.efd) {
            let duration = Date().timeIntervalSince(testRun.startDate ?? Date(timeIntervalSince1970: 0))
            let repeats = context.efd!.slowTestRetries.repeats(for: duration)
            if groupRun.executionCount < Int(repeats) - 1 {
                // We can retry test
                group.retry()
                Log.debug("EFD will retry test \(test.name)")
            } else {
                if repeats == 0 {
                    // Test is too long. EFD failed
                    test.setTag(key: DDEfdTags.testEfdAbortReason, value: DDTagValues.efdAbortSlow)
                }
                if groupRun.canFail {
                    // We don't have previous passed runs.
                    // Record suppressed failures if we have them
                    testRun.recordSuppressedFailures()
                }
            }
        } else if testRun.canFail {
            if let retries = context.retries, // ATR is enabled
               groupRun.executionCount < retries.test, // and we can retry more
               test.module.incrementRetries(max: retries.total) != nil // and increased global retry counter
            {
                // tell group to retry this test
                group.retry()
                Log.debug("ATR will retry test \(test.name)")
            } else {
                // Record suppresses failures if we have them
                testRun.recordSuppressedFailures()
            }
        }
    }
    
    func testCaseRetry(_ testCase: XCTestCase, willRecord issue: XCTIssue) {
        guard case .test(test: let test, group: let group, context: let context) = state else {
            Log.print("testCaseRetry:willRecord: Bad observer state: \(state), expected: .test")
            return
        }
        guard testCase.name.contains(test.name) else {
            Log.print("testCaseRetry:willRecord: Bad test: \(testCase), expected: \(test.name)")
            return
        }
        Log.debug("testCaseRetry:willRecord: \(testCase), issue: \(issue)")
        
        test.setErrorInfo(type: issue.compactDescription, message: issue.description, callstack: nil)
        
        guard let testRun = testCase.testRun as? DDXCTestCaseRetryRun else {
            Log.print("Unknown test run type: \(type(of: testCase.testRun)) for \(testCase)")
            return
        }
        
        // Test can fail more than once.
        // We suppress all errors or none.
        guard testRun.ddTotalFailureCount == 0 else {
            // We already registered failure for this test before.
            if testRun.suppressedFailures.count > 0 { // Check if it was suppressed
                testRun.suppressFailure() // then suppress current error too
                Log.print("Suppressed issue: \(issue) for test: \(testCase)")
            }
            return
        }
        
        if test.module.checkEfdStatus(for: test, efd: context.efd) {
            // EFD enabled for this test. Suppress error for now. We will handle it after
            testRun.suppressFailure()
            Log.print("Suppressed issue \(issue) for test \(testCase)")
        } else if let retries = context.retries, // ATR is enabled
                  let run = group.groupRun, run.executionCount < retries.test, // and we can retry test more
                  test.module.retriedByATRRunsCount < retries.total // and global counter allow us to retry
        {
            testRun.suppressFailure() // suppress current error
            Log.print("Suppressed issue: \(issue) for test: \(testCase)")
        }
    }
}

extension DDTestObserver {
    enum State {
        case none
        case module(DDTestModule)
        case container(suite: ContainerSuite, inside: DDTestModule)
        case suite(suite: DDTestSuite, context: SuiteContext)
        case group(group: DDXCTestRetryGroup, context: GroupContext)
        case test(test: DDTest, group: DDXCTestRetryGroup, context: GroupContext)
    }
    
    indirect enum ContainerSuite {
        case simple(XCTestSuite)
        case nested(XCTestSuite, parent: ContainerSuite)
        
        var suite: XCTestSuite {
            switch self {
            case .simple(let s): return s
            case .nested(let s, parent: _): return s
            }
        }
        
        var parent: ContainerSuite? {
            switch self {
            case .nested(_, parent: let p): return p
            case .simple(_): return nil
            }
        }
        
        init(suite: XCTestSuite, parent: ContainerSuite? = nil) {
            if let parent = parent {
                self = .nested(suite, parent: parent)
            } else {
                self = .simple(suite)
            }
        }
    }
    
    final class SuiteContext {
        let parent: ContainerSuite?
        let skippableTests: SkippableTests?
        let efd: EarlyFlakeDetectionService?
        let retries: (test: UInt, total: UInt)?
        private(set) var unskippableCache: [ObjectIdentifier: UnskippableMethodChecker]
        
        init(parent: ContainerSuite?, skippableTests: SkippableTests?,
             efd: EarlyFlakeDetectionService?, retries: (test: UInt, total: UInt)?)
        {
            self.parent = parent
            self.skippableTests = skippableTests
            self.efd = efd
            self.retries = retries
            self.unskippableCache = [:]
        }
        
        func back(from suite: DDTestSuite) -> State {
            parent == nil ? .module(suite.module) : .container(suite: parent!, inside: suite.module)
        }
        
        func new(suite: XCTestSuite, in module: DDTestModule) -> State {
            let suite = module.suiteStart(name: suite.name)
            return .suite(suite: suite, context: self)
        }
        
        func new(group: DDXCTestRetryGroup, in suite: DDTestSuite, itr: DDTest.ITRStatus) -> State {
            .group(group: group, context: GroupContext(itr: itr, suite: suite, suiteContext: self))
        }
        
        func itr(for group: DDXCTestRetryGroup) -> DDTest.ITRStatus {
            guard let skippableTests = skippableTests else { return .none }
            let checker = unskippableCache.get(key: ObjectIdentifier(group.testClass),
                                               or: group.testClass.unskippableMethods)
            let testId = group.testId
            return DDTest.ITRStatus(canBeSkipped: skippableTests[testId.suite, testId.test] != nil,
                                    markedUnskippable: !checker.canSkip(method: testId.test))
        }
    }
    
    final class GroupContext {
        let itr: DDTest.ITRStatus
        let suite: DDTestSuite
        let suiteContext: SuiteContext
        
        var efd: EarlyFlakeDetectionService? { suiteContext.efd }
        var retries: (test: UInt, total: UInt)? { suiteContext.retries }
        
        init(itr: DDTest.ITRStatus, suite: DDTestSuite, suiteContext: SuiteContext) {
            self.itr = itr
            self.suite = suite
            self.suiteContext = suiteContext
        }
        
        func back() -> State {
            .suite(suite: suite, context: suiteContext)
        }
        
        func new(test: DDTest, in group: DDXCTestRetryGroup) -> State {
            .test(test: test, group: group, context: self)
        }
        
        func back(group: DDXCTestRetryGroup) -> State {
            .group(group: group, context: self)
        }
    }
}
