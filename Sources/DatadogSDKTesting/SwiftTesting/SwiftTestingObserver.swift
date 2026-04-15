/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

protocol SwiftTestingObserverType: Sendable {
    func willStart(suite: borrowing SwiftTestingSuiteContext) async
    func willFinish(suite: borrowing SwiftTestingSuiteContext) async
    func didFinish(suite: borrowing SwiftTestingSuiteContext,
                   active: borrowing SwiftTestingSuiteContext?) async
    
    func willStart(test: borrowing SwiftTestingTestContext) async
    func didFinish(test: borrowing SwiftTestingTestContext) async
    
    func runGroupConfiguration(
        test: borrowing SwiftTestingTestContext
    ) async -> (feature: FeatureId?, configuration: RetryGroupConfiguration)
    func willStart(group: borrowing SwiftTestingRetryGroupContext) async
    func didFinish(group: borrowing SwiftTestingRetryGroupContext) async
    
    func willStart(testRun test: borrowing SwiftTestingTestRunContext,
                   with info: TestRunInfoStart) async
    func shouldSuppressError(for testRun: borrowing SwiftTestingTestRunContext,
                             with info: TestRunInfoStart) -> Bool
    func willFinish(testRun test: borrowing SwiftTestingTestRunContext,
                    withStatus status: SwiftTestingTestStatus,
                    andInfo info: TestRunInfoEnd) async -> (feature: FeatureId?, status: RetryStatus)
    func didFinish(testRun test: borrowing SwiftTestingTestRunContext, with info: TestRunInfoEnd) async
}

struct SwiftTestingObserver: SwiftTestingObserverType {
    func willStart(suite: borrowing SwiftTestingSuiteContext) async {
        DDCrashes.setCurrent(spanData: suite.suite.toCrashData)
        suite.configuration.activeFeatures.testSuiteWillStart(suite: suite.suite,
                                                              testsCount: UInt(suite.testsCount))
    }
    
    func willFinish(suite: borrowing SwiftTestingSuiteContext) async {
        suite.configuration.activeFeatures.testSuiteWillEnd(suite: suite.suite)
    }
    
    func didFinish(suite: borrowing SwiftTestingSuiteContext, active: borrowing SwiftTestingSuiteContext?) async {
        let data1 = active.map { $0.suite.toCrashData }
        let data2 = suite.suite.toCrashData
        DDCrashes.setCurrent(spanData: data1 ?? data2)
        suite.configuration.activeFeatures.testSuiteDidEnd(suite: suite.suite)
    }
    
    func willStart(test: borrowing SwiftTestingTestContext) async {}
    
    func didFinish(test: borrowing SwiftTestingTestContext) async {}
    
    func runGroupConfiguration(
        test: borrowing SwiftTestingTestContext
    ) async -> (feature: FeatureId?, configuration: RetryGroupConfiguration) {
        let (feautre, config) = test.configuration.activeFeatures.testGroupConfiguration(for: test.info.name,
                                                                                         tags: test.attachedTags,
                                                                                         in: test.suite.suite)
        return (feautre?.id, config)
    }
    
    func willStart(group: borrowing SwiftTestingRetryGroupContext) async {
        group.configuration.activeFeatures.testGroupWillStart(for: group.test.info.name,
                                                              in: group.suite.suite)
    }
    
    func didFinish(group: borrowing SwiftTestingRetryGroupContext) async {}
    
    func willStart(testRun test: borrowing SwiftTestingTestRunContext, with info: TestRunInfoStart) async {
        test.configuration.activeFeatures.testWillStart(test: test.testRun, info: info)
    }
    
    func shouldSuppressError(for testRun: borrowing SwiftTestingTestRunContext, with info: TestRunInfoStart) -> Bool {
        if let feature = testRun.configuration.activeFeatures.shouldSuppressError(test: testRun.testRun, info: info) {
            let name = testRun.info.name
            testRun.configuration.log.debug("\(feature) suppressed error in \(name)")
            return true
        }
        return false
    }
    
    func willFinish(testRun test: borrowing SwiftTestingTestRunContext,
                    withStatus status: SwiftTestingTestStatus,
                    andInfo info: TestRunInfoEnd) async -> (feature: FeatureId?, status: RetryStatus)
    {
        var info = info
        let duration = test.configuration.clock.now.timeIntervalSince(test.testRun.startTime)
        let (feature, retryStatus) = test.configuration.activeFeatures.testGroupRetry(test: test.testRun,
                                                                                      duration: duration,
                                                                                      withStatus: status.testStatus,
                                                                                      andInfo: info.toStart)
        info.retry = (feature?.id, retryStatus)
        test.configuration.activeFeatures.testWillFinish(test: test.testRun,
                                                         duration: duration,
                                                         withStatus: status.testStatus,
                                                         andInfo: info)
        return info.retry
    }
    
    func didFinish(testRun test: borrowing SwiftTestingTestRunContext, with info: TestRunInfoEnd) async {
        test.configuration.activeFeatures.testDidFinish(test: test.testRun, info: info)
    }
}
