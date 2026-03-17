//
//  SwiftTestingObserver.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 17/03/2026.
//

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
