/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

protocol SwiftTestingObserverType: AnyObject, Sendable {
    func willStart(suite: any SwiftTestingSuiteContextType) async
    func didFinish(suite: any SwiftTestingSuiteContextType) async
    
    func willStart(test: any SwiftTestingTestContextType) async
    func didFinish(test: any SwiftTestingTestContextType) async
    
    func runGroupConfiguration(test: any SwiftTestingTestContextType) async -> RetryGroupConfiguration
    func willStart(group: any SwiftTestingRetryGroupContextType) async
    func didFinish(group: any SwiftTestingRetryGroupContextType) async
    
    func willStart(testRun test: any SwiftTestingTestRunContextType) async
    func shouldSuppressError(for testRun: some SwiftTestingTestRunContextType) -> Bool
    func willFinish(testRun test: any SwiftTestingTestRunContextType, with status: SwiftTestingTestStatus) async -> SwiftTestingTestRunRetry
    func didFinish(testRun test: any SwiftTestingTestRunContextType) async
}
