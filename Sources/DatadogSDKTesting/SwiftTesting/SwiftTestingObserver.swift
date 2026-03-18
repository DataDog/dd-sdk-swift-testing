/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

protocol SwiftTestingObserverType: AnyObject, Sendable {
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
