/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

protocol SwiftTestingObserverType: AnyObject, Sendable, TestSessionManagerObserver {
    func willStart(module: any TestModule) async
    func didFinish(module: any TestModule) async
    
    func willStart(suite: borrowing SwiftTestingSuiteContext) async
    func didFinish(suite: borrowing SwiftTestingSuiteContext) async
    
    func willStart(test: borrowing SwiftTestingTestContext) async
    func didFinish(test: borrowing SwiftTestingTestContext) async
    
    func runGroupConfiguration(test: borrowing SwiftTestingTestContext) async -> RetryGroupConfiguration
    func willStart(group: borrowing SwiftTestingRetryGroupContext) async
    func didFinish(group: borrowing SwiftTestingRetryGroupContext) async
    
    func willStart(testRun test: borrowing SwiftTestingTestRunContext) async
    func shouldSuppressError(for testRun: borrowing SwiftTestingTestRunContext) -> Bool
    func willFinish(testRun test: borrowing SwiftTestingTestRunContext, with status: SwiftTestingTestStatus) async -> SwiftTestingTestRunRetry
    func didFinish(testRun test: borrowing SwiftTestingTestRunContext) async
}

final class SwiftTestingObserver: SwiftTestingObserverType {
    func willStart(session: any TestSession, with config: SessionConfig) async {
    }
    
    func didFinish(session: any TestSession, with config: SessionConfig) async {
    }
    
    func willStart(module: any TestModule) async {
        DDCrashes.setCurrent(spanData: module.toCrashData)
    }
    
    func didFinish(module: any TestModule) async {
        DDCrashes.setCurrent(spanData: nil)
    }
    
    func willStart(suite: borrowing SwiftTestingSuiteContext) async {
        DDCrashes.setCurrent(spanData: suite.suite.toCrashData)
    }
    
    func didFinish(suite: borrowing SwiftTestingSuiteContext) async {
        DDCrashes.setCurrent(spanData: suite.suite.module.toCrashData)
    }
    
    func willStart(test: borrowing SwiftTestingTestContext) async {
    }
    
    func didFinish(test: borrowing SwiftTestingTestContext) async {
    }
    
    func runGroupConfiguration(test: borrowing SwiftTestingTestContext) async -> RetryGroupConfiguration {
        .retry(.init())
    }
    
    func willStart(group: borrowing SwiftTestingRetryGroupContext) async {
    }
    
    func didFinish(group: borrowing SwiftTestingRetryGroupContext) async {
    }
    
    func willStart(testRun test: borrowing SwiftTestingTestRunContext) async {
    }
    
    func shouldSuppressError(for testRun: borrowing SwiftTestingTestRunContext) -> Bool {
        false
    }
    
    func willFinish(testRun test: borrowing SwiftTestingTestRunContext, with status: SwiftTestingTestStatus) async -> SwiftTestingTestRunRetry {
        .retry(.end(errors: .unsuppressed))
    }
    
    func didFinish(testRun test: borrowing SwiftTestingTestRunContext) async {
    }
}
