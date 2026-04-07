/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter
internal import XCTest

final class DDXCTestObserver: NSObject, XCTestObservation, DDXCTestRetryDelegate {
    private(set) var state: State
    private let log: Logger

    init(session: any TestSessionManager, log: Logger) {
        XCUIApplication.swizzleMethods
        state = .start(session)
        self.log = log
        super.init()
    }

    func start() {
        switch state {
        case .start, .stopped:
            XCTestObservationCenter.shared.addTestObserver(self)
        default: break
        }
    }

    func stop() {
        switch state {
        case .stopping, .start:
            XCTestObservationCenter.shared.removeTestObserver(self)
            state = .stopped
        default: break
        }
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        guard case .start(let manager) = state else {
            log.print("testBundleWillStart: Bad observer state: \(state), expected: .none")
            return
        }
        
        let bundleName = testBundle.name
        
        do {
            let session = try waitForAsync { try await manager.sessionAndConfig }
            let module = session.session.module(named: bundleName)
            state = .module(module: module, context: ModuleContext(session: session.session,
                                                                   config: session.config))
            log.debug("testBundleWillStart: \(bundleName)")
        } catch {
            log.print("Session initialisation failed: \(error)")
            state = .startError(error)
            return
        }
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        guard case .module(module: let module, context: let context) = state else {
            log.print("testBundleDidFinish: Bad observer state: \(state), expected: .module")
            return
        }
        state = .stopping
        stop()
        guard module.name == testBundle.name else {
            log.print("testBundleDidFinish: Bad module: \(testBundle.name), expected: \(module.name)")
            return
        }
        context.session.end(module: module)
        log.debug("testBundleDidFinish: \(module.name)")
    }

    func testSuiteWillStart(_ testSuite: XCTestSuite) {
        let module: any TestModule & TestSuiteProvider
        let parent: ContainerSuite?
        let context: ModuleContext
        
        switch state {
        case .module(module: let mod, context: let cont):
            module = mod
            parent = nil
            context = cont
        case .container(suite: let contr, inside: let mod, context: let contxt):
            module = mod
            parent = contr
            context = contxt
        case .startError(let err):
            log.print("testSuiteWillStart: Failed, module config error \(err)")
            testSuite.testRun?.stop()
            exit(1)
        default:
            log.print("testSuiteWillStart: Bad observer state: \(state), expected: .module or .container")
            return
        }

        guard let tests = testSuite.tests as? [XCTestCase] else {
            log.debug("testSuiteWillStart: container \(testSuite.name)")
            state = .container(suite: ContainerSuite(suite: testSuite, parent: parent), inside: module, context: context)
            return
        }
        
        let wrappedTests = tests.map { DDXCTestRetryGroup(for: $0, observer: self) }
        testSuite.setValue(wrappedTests, forKey: "_mutableTests")
        
        let suite = module.startSuite(named: testSuite.name, at: nil, framework: "XCTest")
        DDCrashes.setCurrent(spanData: suite.toCrashData)
        context.features.testSuiteWillStart(suite: suite, testsCount: UInt(wrappedTests.count))
        
        state = .suite(suite: suite, context: SuiteContext(parent: parent, module: module, context: context))
        log.debug("testSuiteWillStart: \(testSuite.name)")
    }

    func testSuiteDidFinish(_ testSuite: XCTestSuite) {
        switch state {
        case .container(suite: let suite, inside: let module, context: let context):
            guard suite.suite.name == testSuite.name else {
                log.print("testSuiteDidFinish: Bad suite: \(testSuite.name), expected: \(suite.suite.name)")
                return
            }
            state = suite.parent == nil
                ? .module(module: module, context: context)
                : .container(suite: suite.parent!, inside: module, context: context)
            log.debug("testSuiteDidFinish: container \(testSuite.name)")
        case .suite(suite: let suite, context: let context):
            guard suite.name == testSuite.name else {
                log.print("testSuiteDidFinish: Bad suite: \(testSuite.name), expected: \(suite.name)")
                return
            }
            // Set suite status based on it's test groups.
            // Features will setup proper skip and fail strategies for the groups.
            suite.set(status: testSuite.testRun?.status ?? .pass)
            context.features.testSuiteWillEnd(suite: suite)
            suite.end()
            state = context.back(from: suite)
            DDCrashes.setCurrent(spanData: context.module.toCrashData)
            context.features.testSuiteDidEnd(suite: suite)
            log.debug("testSuiteDidFinish: \(testSuite.name)")
        default:
            log.print("testSuiteDidFinish: Bad observer state: \(state), expected: .suite or .container")
        }
    }
    
    func testRetryGroupWillStart(_ group: any DDXCTestRetryGroupType) {
        guard case .suite(suite: let suite, context: let context) = state else {
            log.print("testRetryGroupWillStart: Bad observer state: \(state), expected: .suite")
            return
        }
        
        let testId = group.testId
        let (feature, config) = context.features.testGroupConfiguration(for: testId.test,
                                                                        meta: group.currentTest!,
                                                                        in: suite)
        
        group.groupRun?.skipStrategy = config.skipStrategy.xcTest
        group.groupRun?.successStrategy = config.successStrategy.xcTest
        
        var skip: (by: (feature: FeatureId, reason: String)?, status: SkipStatus) = (nil, config.skipStatus)
        if let feature = feature, case .skip(let reason, _) = config {
            group.skip(reason: reason)
            skip.by = (feature.id, reason)
        }
        
        group.context = GroupContext(skip: skip, suite: suite, suiteContext: context)
        
        context.features.testGroupWillStart(for: testId.test, in: suite)
        
        state = .group
        log.debug("testRetryGroupWillStart: \(group.name)")
    }
    
    func testRetryGroupDidFinish(_ group: any DDXCTestRetryGroupType) {
        guard case .group = state else {
            log.print("testRetryGroupDidFinish: Bad observer state: \(state), expected: .group")
            return
        }
        state = group.context.back()
        log.debug("testRetryGroupDidFinish: \(group.name), " +
                  "executions: \(group.groupRun?.executionCount ?? 0), " +
                  "failed: \(group.groupRun?.failedExecutionCount ?? 0)")
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        guard case .group = state else {
            log.print("testCaseWillStart: Bad observer state: \(state), expected: .group")
            return
        }
        guard let testRun = testCase.testRun as? DDXCTestCaseRetryRunType else {
            log.print("testCaseWillStart: Unknown test run type: \(type(of: testCase.testRun)) for \(testCase)")
            return
        }
        let test = testRun.ddTest
        let info = TestRunInfoStart(skip: testRun.context.skip,
                                    retry: testRun.context.retryStart,
                                    executions: (total: testRun.group.groupRun?.executionCount ?? 0,
                                                 failed: testRun.group.groupRun?.failedExecutionCount ?? 0))
        testRun.context.features.testWillStart(test: test, info: info)
        
        state = .test
        log.debug("testCaseWillStart: \(testCase.name)")
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        guard case .test = state else {
            log.print("testCaseDidFinish: Bad observer state: \(state), expected: .test")
            return
        }
        guard let testRun = testCase.testRun as? DDXCTestCaseRetryRunType else {
            log.print("testCaseDidFinish: Unknown test run type: \(type(of: testCase.testRun)) for \(testCase)")
            return
        }
        let test = testRun.ddTest
        test.addBenchmarkTagsIfNeeded(from: testCase)
        test.set(status: testCase.testRun?.status ?? .fail)
        log.debug("testCaseDidFinish: \(testCase.name)")
    }
    
    func testCaseRetryWillFinish(_ testCase: XCTestCase) {
        guard case .test = state else {
            log.print("testCaseRetryWillFinish: Bad observer state: \(state), expected: .test")
            return
        }
        log.debug("testCaseRetryWillFinish: \(testCase)")
        guard let testRun = testCase.testRun as? DDXCTestCaseRetryRunType else {
            log.print("testCaseRetryWillFinish: Unknown test run type: \(type(of: testCase.testRun)) for \(testCase)")
            return
        }
        guard let groupRun = testRun.group.groupRun else {
            log.print("testCaseRetryWillFinish: Bad observer state. Group run in nil")
            testRun.recordSuppressedFailures()
            return
        }
        
        let duration = Date().timeIntervalSince(testRun.startDate ?? Date(timeIntervalSince1970: 0))
        let status: TestStatus = testRun.hasBeenSkipped ? .skip : testRun.canFail ? .fail : .pass
        
        // Test was skipped by developer / xcode / etc.
        if testRun.hasBeenSkipped && testRun.context.skip.by == nil {
            testRun.context.skip.by = (feature: .notFeature,
                                       reason: testRun.skipReason ?? "Skipped in the code")
        }
        
        let startInfo = TestRunInfoStart(skip: testRun.context.skip,
                                         retry: testRun.context.retryStart,
                                         executions: (total: groupRun.executionCount,
                                                      failed: groupRun.failedExecutionCount))
        
        let (feature, retryStatus) = testRun.context.features.testGroupRetry(test: testRun.ddTest, duration: duration,
                                                                             withStatus: status, andInfo: startInfo)
        
        // save retry status
        testRun.context.retry = (feature: feature?.id, status: retryStatus)
        
        // Restore errors if needed
        if testRun.suppressedFailures.count > 0 {
            switch retryStatus.errorsStatus {
            case .suppressed(let reason):
                testRun.recordSuppressedFailuresAsExpected(reason: reason)
            case .unsuppressed:
                if let reason = feature?.id {
                    log.debug("\(reason) restores suppressed failures for \(testRun.ddTest.name)")
                } else {
                    log.debug("restored suppressed failures for \(testRun.ddTest.name)")
                }
                testRun.recordSuppressedFailures()
            }
        }
        
        // update info with the new retry status
        let endInfo = TestRunInfoEnd(skip: startInfo.skip,
                                     retry: testRun.context.retry,
                                     executions: startInfo.executions)
        // Run hook
        testRun.context.features.testWillFinish(test: testRun.ddTest, duration: duration, withStatus: status, andInfo: endInfo)
        
        // Start retry if needed
        if case .retry(let reason, _) = retryStatus {
            log.debug("will retry test \(testRun.ddTest.name), reason: \(reason)")
            testRun.group.retry()
        }
    }
    
    func testCaseRetryDidFinish(_ testCase: XCTestCase) {
        guard case .test = state else {
            log.print("testCaseRetryDidFinish: Bad observer state: \(state), expected: .test")
            return
        }
        guard let testRun = testCase.testRun as? DDXCTestCaseRetryRunType else {
            log.print("testCaseRetryDidFinish: Unknown test run type: \(type(of: testCase.testRun)) for \(testCase)")
            return
        }
        guard let groupRun = testRun.group.groupRun else {
            log.print("testCaseRetryDidFinish: Bad observer state. Group run in nil")
            return
        }
        // Run end hook. We can't run it in testCaseDidFinish because test isn't ended yet
        let info = TestRunInfoEnd(skip: testRun.context.skip,
                                  retry: testRun.context.retry,
                                  executions: (total: groupRun.executionCount,
                                               failed: groupRun.failedExecutionCount))
        testRun.context.features.testDidFinish(test: testRun.ddTest, info: info)
        // Switch state back
        state = .group
        log.debug("testCaseRetryDidFinish: \(testCase.name)")
    }
    
    func testCaseRetry(_ testCase: XCTestCase, willRecord issue: XCTIssue) {
        guard case .test = state else {
            log.print("testCaseRetry:willRecord: Bad observer state: \(state), expected: .test")
            return
        }
        log.debug("testCaseRetry:willRecord: \(testCase), issue: \(issue)")
        
        guard let testRun = testCase.testRun as? DDXCTestCaseRetryRunType else {
            log.print("testCaseRetry:willRecord: Unknown test run type: \(type(of: testCase.testRun)) for \(testCase)")
            return
        }
        
        // Test can fail more than once.
        // We suppress all errors or none.
        guard testRun.ddTotalFailureCount == 0 else {
            // We already registered failure for this test before.
            if testRun.suppressedFailures.count > 0 { // Check if it was suppressed
                testRun.suppressFailure() // then suppress current error too
                log.debug("Suppressed one more issue: \(issue) for test: \(testCase)")
            }
            return
        }
        
        let info = TestRunInfoStart(skip: testRun.context.skip,
                                    retry: testRun.context.retryStart,
                                    executions: (total: testRun.group.groupRun?.executionCount ?? 0,
                                                 failed: testRun.group.groupRun?.failedExecutionCount ?? 0))
        
        if let feature = testRun.context.features.shouldSuppressError(test: testRun.ddTest, info: info) {
            testRun.suppressFailure()
            log.debug("Suppressed issue \(issue) for test \(testCase) by feature \(feature.id)")
        }
    }
    
    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        guard case .test = state else {
            log.print("testCase:didRecord: Bad observer state: \(state), expected: .test")
            return
        }
        guard let testRun = testCase.testRun as? DDXCTestCaseRetryRunType else {
            log.print("testCase:didRecord: Unknown test run type: \(type(of: testCase.testRun)) for \(testCase)")
            return
        }
        log.debug("testCase:didRecord: \(testCase), issue: \(issue)")
        
        testRun.ddTest.add(error: .init(type: issue.compactDescription.components(separatedBy: " ").first ?? "unknown",
                                        message: issue.description))
    }
    
    func testCase(_ testCase: XCTestCase, didRecord expectedFailure: XCTExpectedFailure) {
        guard case .test = state else {
            log.print("testCase:didRecord:expectedFailure: Bad observer state: \(state), expected: .test")
            return
        }
        guard let testRun = testCase.testRun as? DDXCTestCaseRetryRunType else {
            log.print("testCase:didRecord:expectedFailure: Unknown test run type: \(type(of: testCase.testRun)) for \(testCase)")
            return
        }
        log.debug("testCase:didRecord: \(testCase), expectedFailure: \(expectedFailure.issue.compactDescription)")
        
        let reason = expectedFailure.failureReason ?? ""
        let type = expectedFailure.issue.compactDescription.components(separatedBy: " ").first ?? "unknown"
        
        testRun.ddTest.add(error: .init(type: "ExpectedFailure[\(reason)]: " + type,
                                        message: expectedFailure.issue.description))
    }
}

extension DDXCTestObserver {
    enum State {
        case start(any TestSessionManager)
        case startError(any Error)
        case stopping
        case stopped
        case module(module: any TestModule & TestSuiteProvider, context: ModuleContext)
        case container(suite: ContainerSuite, inside: any TestModule & TestSuiteProvider, context: ModuleContext)
        case suite(suite: any TestSuite & TestRunProvider, context: SuiteContext)
        case group
        case test
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
    
    final class ModuleContext {
        let session: any TestSession & TestModuleManager
        let config: SessionConfig
        
        var features: [any TestHooksFeature] { config.activeFeatures }
        
        init(session: any TestSession & TestModuleManager, config: SessionConfig) {
            self.session = session
            self.config = config
        }
    }
    
    final class SuiteContext {
        let parent: ContainerSuite?
        let module: any TestModule & TestSuiteProvider
        let moduleContext: ModuleContext
        var features: [any TestHooksFeature] { moduleContext.features }
        
        init(parent: ContainerSuite?, module: any TestModule & TestSuiteProvider, context: ModuleContext)
        {
            self.parent = parent
            self.module = module
            self.moduleContext = context
        }
        
        func back(from suite: any TestSuite) -> State {
            parent == nil ?
                .module(module: module, context: moduleContext) :
                .container(suite: parent!,
                           inside: module,
                           context: moduleContext)
        }
    }
    
    final class GroupContext {
        let suite: any TestSuite & TestRunProvider
        let suiteContext: SuiteContext
        
        var skip: (by: (feature: FeatureId, reason: String)?, status: SkipStatus)
        var retry: (feature: FeatureId?, status: RetryStatus)
        
        var features: [any TestHooksFeature] { suiteContext.features }
        
        var retryStart: (feature: FeatureId, reason: String, errors: RetryStatus.ErrorsStatus)? {
            retry.feature.flatMap { id in retry.status.retryReason.map { (id, $0) } }.map {
                (feature: $0, reason: $1, errors: retry.status.errorsStatus)
            }
        }
        
        init(skip: (by: (feature: FeatureId, reason: String)?, status: SkipStatus),
             suite: any TestSuite & TestRunProvider,
             suiteContext: SuiteContext)
        {
            self.skip = skip
            self.suite = suite
            self.suiteContext = suiteContext
            self.retry = (nil, .end(errors: .unsuppressed))
        }
        
        func back() -> State {
            .suite(suite: suite, context: suiteContext)
        }
    }
}
