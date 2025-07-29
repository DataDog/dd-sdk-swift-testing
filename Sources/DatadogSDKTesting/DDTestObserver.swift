/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter
internal import XCTest

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
        let session = Session.start(name: "XCTest.session",
                                    command: DDTestMonitor.env.testCommand)
        session.testFramework = "XCTest"
        Log.debug("testBundleWillStart: \(bundleName)")
        state = session.configError ? .configError : .module(session.moduleStart(name: bundleName))
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        guard case .module(let module) = state else {
            Log.print("testBundleDidFinish: Bad observer state: \(state), expected: .module")
            return
        }
        guard module.name == testBundle.name else {
            Log.print("testBundleDidFinish: Bad module: \(testBundle.name), expected: \(module.name)")
            state = .none
            return
        }
        module.end()
        state = .none
        Log.debug("testBundleDidFinish: \(module.name)")
        
        // Fail session if module failed
        if case .fail = module.status {
            module.session.set(failed: nil)
        }
        module.session.end()
    }

    func testSuiteWillStart(_ testSuite: XCTestSuite) {
        let module: Module
        let parent: ContainerSuite?
        
        switch state {
        case .module(let mod):
            module = mod
            parent = nil
        case .container(suite: let cont, inside: let mod):
            module = mod
            parent = cont
        case .configError:
            Log.print("testSuiteWillStart: Failed, module config error")
            testSuite.testRun?.stop()
            exit(1)
        default:
            Log.print("testSuiteWillStart: Bad observer state: \(state), expected: .module or .container")
            return
        }

        guard let tests = testSuite.tests as? [XCTestCase] else {
            Log.debug("testSuiteWillStart: container \(testSuite.name)")
            state = .container(suite: ContainerSuite(suite: testSuite, parent: parent), inside: module)
            return
        }

        let features = Log.measure(name: "waiting for test optimization to be started") {
            DDTestMonitor.instance?.activeFeatures ?? []
        }
        
        let wrappedTests = tests.map { DDXCTestRetryGroup(for: $0) }
        testSuite.setValue(wrappedTests, forKey: "_mutableTests")
        
        let suite = module.suiteStart(name: testSuite.name)
        
        for feature in features {
            feature.testSuiteWillStart(suite: suite, testsCount: UInt(wrappedTests.count))
        }
        
        state = .suite(suite: suite, context: SuiteContext(parent: parent, features: features))
        
//        state = SuiteContext(
//            parent: parent,
//            tia: DDTestMonitor.instance?.tia,
//            knownTests: DDTestMonitor.instance?.knownTests,
//            efd: DDTestMonitor.instance?.efd,
//            atr: DDTestMonitor.instance?.atr,
//            testManagement: DDTestMonitor.instance?.testManagement
//        ).new(suite: testSuite, in: module)
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
            // Set suite status based on it's test groups.
            // Features will setup proper skip and fail strategies for the groups.
            suite.set(status: testSuite.testRun?.status ?? .pass)
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
        
        let (config, featureId, _) = context.features.reduce((TestRetryGroupConfiguration.Configuration(), "", false)) { prev, feature in
            guard !prev.2 else { return prev }
            let (config, stop) = prev.0.next(with: feature.testGroupConfiguration(for: group.name, meta: group.currentTest!, in: suite))
            return (config, feature.id, stop)
        }
        
        group.groupRun?.skipStrategy = config.skipStrategy.xcTest
        group.groupRun?.successStrategy = config.successStrategy.xcTest
        
        let skipStatus = config.skipStatus
        if skipStatus.isSkipped {
            group.skip(reason: featureId)
        }
        
        for feature in context.features {
            feature.testGroupWillStart(for: group.name, in: suite)
        }
        
        state = context.new(group: group, in: suite, skipStatus: skipStatus)
        
//        group.groupRun?.successStrategy = .atLeastOneSucceeded
//        let tia = context.tiaStatus(for: group)
//        if tia.markedUnskippable { suite.unskippable = true }
//        if tia.skipped { group.skip(reason: "ITR") }
//        state = context.new(group: group, in: suite, tia: tia)
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
        let test = context.suite.testStart(name: testCase.testId.test)
        
        for feature in context.features {
            feature.testWillStart(test: test, retryReason: group.retryReason,
                                  skipStatus: context.skipStatus,
                                  executionCount: group.groupRun?.executionCount ?? 0,
                                  failedExecutionCount: group.groupRun?.failedExecutionCount ?? 0)
        }
//        if context.isNewTest(group: group) {
//            test.setTag(key: DDTestTags.testIsNew, value: "true")
//            if group.retryReason == nil {
//                context.efd?.incrementNewTests()
//            }
//        }
//        if let retryReason = group.retryReason {
//            test.setTag(key: DDEfdTags.testIsRetry, value: "true")
//            test.setTag(key: DDEfdTags.testRetryReason, value: retryReason)
//        }
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
        
        let duration = Date().timeIntervalSince(testRun.startDate ?? Date(timeIntervalSince1970: 0))
        let status: TestStatus = testRun.hasBeenSkipped ? .skip : testRun.canFail ? .fail : .pass
        for feature in context.features {
            feature.testWillFinish(test: test, duration: duration, withStatus: status,
                                   skipStatus: context.skipStatus,
                                   executionCount: groupRun.executionCount,
                                   failedExecutionCount: groupRun.failedExecutionCount)
        }
        
        let actionAndFeature: (RetryStatus, String)? = context.features.reduce(nil) { prev, feature in
            guard prev == nil else { return prev }
            return feature.testGroupRetry(test: test, duration: duration, withStatus: status,
                                          skipStatus: context.skipStatus,
                                          executionCount: groupRun.executionCount,
                                          failedExecutionCount: groupRun.failedExecutionCount).map {
                ($0, feature.id)
            }
        }
        
        guard let actionAndFeature = actionAndFeature else { return }
        
        switch actionAndFeature {
        case (.retry, let id):
            Log.debug("\(id) will retry test \(test.name)")
            group.retry(reason: id)
        case (.recordErrors, let id):
            if testRun.canFail {
                Log.debug("\(id) restores suppressed failures for \(test.name)")
                testRun.recordSuppressedFailures()
            }
        case (.pass, _): break
        }
//
//        if let efd = context.efd, efd.checkStatus(for: test) {
//            let duration = Date().timeIntervalSince(testRun.startDate ?? Date(timeIntervalSince1970: 0))
//            let repeats = efd.slowTestRetries.repeats(for: duration)
//            if groupRun.executionCount < Int(repeats) - 1 {
//                // We can retry test
//                group.retry(reason: DDTagValues.retryReasonEfd)
//                Log.debug("EFD will retry test \(test.name)")
//            } else {
//                if repeats == 0 {
//                    // Test is too long. EFD failed
//                    test.setTag(key: DDEfdTags.testEfdAbortReason, value: DDTagValues.efdAbortSlow)
//                }
//                if groupRun.canFail {
//                    // We don't have previous passed runs.
//                    // Record suppressed failures if we have them
//                    testRun.recordSuppressedFailures()
//                }
//            }
//        } else if testRun.canFail {
//            if let retries = context.retries, // ATR is enabled
//               groupRun.executionCount < retries.test, // and we can retry more
//               test.module.incrementRetries(max: retries.total) != nil // and increased global retry counter
//            {
//                // tell group to retry this test
//                group.retry(reason: DDTagValues.retryReasonAtr)
//                Log.debug("ATR will retry test \(test.name)")
//            } else {
//                // Record suppresses failures if we have them
//                testRun.recordSuppressedFailures()
//            }
//        }
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
                Log.print("Suppressed one more issue: \(issue) for test: \(testCase)")
            }
            return
        }
        
        let suppress = context.features.reduce((false, "")) { prev, feature in
            guard !prev.0 else { return prev }
            let suppress =  feature.shouldSuppressError(test: test, skipStatus: context.skipStatus,
                                                        executionCount: group.groupRun?.executionCount ?? 0,
                                                        failedExecutionCount: group.groupRun?.failedExecutionCount ?? 0)
            return (suppress, feature.id)
        }
        
        if suppress.0 {
            testRun.suppressFailure()
            Log.print("Suppressed issue \(issue) for test \(testCase) reason \(suppress.1)")
        }
    }
}

extension DDTestObserver {
    enum State {
        case none
        case configError
        case module(Module)
        case container(suite: ContainerSuite, inside: Module)
        case suite(suite: Suite, context: SuiteContext)
        case group(group: DDXCTestRetryGroup, context: GroupContext)
        case test(test: Test, group: DDXCTestRetryGroup, context: GroupContext)
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
        let features: [any TestHooksFeature]
//        let tia: TestImpactAnalysis?
//        let knownTests: KnownTests?
//        let efd: EarlyFlakeDetection?
//        let atr: AutomaticTestRetries?
//        let testManagement: TestManagement?
        
        init(parent: ContainerSuite?, features: [any TestHooksFeature])
        {
            self.parent = parent
            self.features = features
        }
        
//        init(parent: ContainerSuite?,
//             tia: TestImpactAnalysis?, knownTests: KnownTests?,
//             efd: EarlyFlakeDetection?, atr: AutomaticTestRetries?,
//             testManagement: TestManagement?)
//        {
//            self.parent = parent
//            self.tia = tia
//            self.knownTests = knownTests
//            self.efd = efd
//            self.atr = atr
//            self.testManagement = testManagement
//        }
        
        func back(from suite: Suite) -> State {
            parent == nil ?
                .module(suite.module as! Module) :
                .container(suite: parent!, inside: suite.module as! Module)
        }
        
//        func new(suite: XCTestSuite, in module: DDTestModule) -> State {
//            let suite = module.suiteStart(name: suite.name)
//            return .suite(suite: suite, context: self)
//        }
        
        func new(group: DDXCTestRetryGroup, in suite: Suite, skipStatus: SkipStatus) -> State {
            .group(group: group, context: GroupContext(skipStatus: skipStatus, suite: suite, suiteContext: self))
        }
        
//        func tiaStatus(for group: DDXCTestRetryGroup) -> TestImpactAnalysis.Status {
//            let testId = group.testId
//            return tia?.status(for: group.testClass, named: testId.test, in: testId.suite) ?? .none
//        }
    }
    
    final class GroupContext {
        //let tia: TestImpactAnalysis.Status
        let suite: Suite
        let suiteContext: SuiteContext
        let skipStatus: SkipStatus
        
        var features: [any TestHooksFeature] { suiteContext.features }
        
//        var knownTests: KnownTests? { suiteContext.knownTests }
//        var efd: EarlyFlakeDetection? { suiteContext.efd }
//        var atr: AutomaticTestRetries? { suiteContext.atr }
//        var testManagement: TestManagement? { suiteContext.testManagement }
        
        init(skipStatus: SkipStatus, suite: Suite, suiteContext: SuiteContext) {
            self.skipStatus = skipStatus
            self.suite = suite
            self.suiteContext = suiteContext
        }
        
        func back() -> State {
            .suite(suite: suite, context: suiteContext)
        }
        
//        func isNewTest(group: DDXCTestRetryGroup) -> Bool {
//            let id = group.testId
//            return knownTests?.isNew(test: id.test, in: id.suite, and: suite.module.bundleName) ?? false
//        }
        
        func new(test: Test, in group: DDXCTestRetryGroup) -> State {
            .test(test: test, group: group, context: self)
        }
        
        func back(group: DDXCTestRetryGroup) -> State {
            .group(group: group, context: self)
        }
    }
}
