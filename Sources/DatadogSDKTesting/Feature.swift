/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

protocol Feature: AnyObject {
    static var id: String { get }
    func stop()
}

extension Feature {
    var id: String { Self.id }
}

protocol TestHooksFeature: Feature {
    // Start of the suite
    func testSuiteWillStart(suite: any TestSuite, testsCount: UInt) -> Void
    // Start of the test case
    func testGroupWillStart(for test: String, in suite: any TestSuite) -> Void
    // Configuration for retry group. Will use the first which is not .next
    func testGroupConfiguration(for test: String, meta: UnskippableMethodCheckerFactory,
                                in suite: any TestSuite,
                                configuration: TestRetryGroupConfiguration.Configuration) -> TestRetryGroupConfiguration
    // Called for the each test run in the group. First test run will have nil retry reason
    // executionCount and failedExecutionCount doesn't have the current run yet
    func testWillStart(test: any TestRun, retryReason: String?, skipStatus: SkipStatus,
                       executionCount: Int, failedExecutionCount: Int) -> Void
    // executionCount and failedExecutionCount doesn't have the current run yet
    func testWillFinish(test: any TestRun, duration: TimeInterval, withStatus: TestStatus,
                        skipStatus: SkipStatus, executionCount: Int, failedExecutionCount: Int) -> Void
    // Feature could return retry status. First non nil one will be used
    // executionCount and failedExecutionCount doesn't have the current run yet
    func testGroupRetry(test: any TestRun, duration: TimeInterval, withStatus: TestStatus,
                        skipStatus: SkipStatus, executionCount: Int, failedExecutionCount: Int) -> RetryStatus?
    // Called for the first error in the test run
    func shouldSuppressError(test: any TestRun, skipStatus: SkipStatus, executionCount: Int, failedExecutionCount: Int) -> Bool
}

protocol FeatureFactory {
    associatedtype FT: Feature
    
    static func isEnabled(config: Config, env: Environment, remote: TracerSettings) -> Bool
    func create(log: Logger) -> FT?
}

enum TestRetryGroupConfiguration {
    struct Configuration {
        let skipStatus: SkipStatus
        let skipStrategy: RetryGroupSkipStrategy
        let successStrategy: RetryGroupSuccessStrategy
        
        init(skipStatus: SkipStatus = .normalRun,
             skipStrategy: RetryGroupSkipStrategy = .allSkipped,
             successStrategy: RetryGroupSuccessStrategy = .allSucceeded)
        {
            self.skipStatus = skipStatus
            self.skipStrategy = skipStrategy
            self.successStrategy = successStrategy
        }
        
        func updated(skipStatus: SkipStatus? = nil,
                     skipStrategy: RetryGroupSkipStrategy? = nil,
                     successStrategy: RetryGroupSuccessStrategy? = nil) -> Self
        {
            .init(skipStatus: skipStatus ?? self.skipStatus,
                  skipStrategy: skipStrategy ?? self.skipStrategy,
                  successStrategy: successStrategy ?? self.successStrategy)
        }
        
        func next(skipStatus: SkipStatus? = nil,
                  skipStrategy: RetryGroupSkipStrategy? = nil,
                  successStrategy: RetryGroupSuccessStrategy? = nil) -> TestRetryGroupConfiguration
        {
            .next(updated(skipStatus: skipStatus, skipStrategy: skipStrategy, successStrategy: successStrategy))
        }
        
        func skip(status: SkipStatus, strategy skip: RetryGroupSkipStrategy) -> TestRetryGroupConfiguration {
            .skip(updated(skipStatus: status, skipStrategy: skip))
        }
        
        func retry(strategy success: RetryGroupSuccessStrategy) -> TestRetryGroupConfiguration {
            .retry(updated(successStrategy: success))
        }
    }
    
    case next(Configuration)
    case skip(Configuration)
    case retry(Configuration)
    
    var hasNext: Bool {
        switch self {
        case .next: return true
        default: return false
        }
    }
    
    var configuration: Configuration {
        switch self {
        case .next(let config): return config
        case .skip(let config): return config
        case .retry(let config): return config
        }
    }
    
    var skipStatus: SkipStatus { configuration.skipStatus }
    var skipStrategy: RetryGroupSkipStrategy { configuration.skipStrategy }
    var successStrategy: RetryGroupSuccessStrategy { configuration.successStrategy }
}

enum RetryGroupSuccessStrategy {
    case allSucceeded
    case atLeastOneSucceeded
    case atMostOneFailed
}

enum RetryGroupSkipStrategy {
    case allSkipped
    case atLeastOneSkipped
}

struct SkipStatus {
    let canBeSkipped: Bool
    let markedUnskippable: Bool

    var isForcedRun: Bool { canBeSkipped && markedUnskippable }
    var isSkipped: Bool { canBeSkipped && !markedUnskippable }

    @inlinable
    static var normalRun: Self {
        .init(canBeSkipped: false, markedUnskippable: false)
    }
}

enum RetryStatus: Equatable, Hashable {
    // Pass current test and suppress all errors
    case pass
    // Retry current test and suppress all errors
    case retry
    // Fail current test if it has errors
    case recordErrors
}

extension TestHooksFeature {
    func testSuiteWillStart(suite: any TestSuite, testsCount: UInt) {}
    func testGroupWillStart(for test: String, in suite: any TestSuite) {}
    func testGroupConfiguration(for test: String, meta: UnskippableMethodCheckerFactory,
                                in suite: any TestSuite,
                                configuration: TestRetryGroupConfiguration.Configuration) -> TestRetryGroupConfiguration
    {
        return configuration.next()
    }
    func testWillStart(test: any TestRun, retryReason: String?, skipStatus: SkipStatus,
                       executionCount: Int, failedExecutionCount: Int) {}
    func testWillFinish(test: any TestRun, duration: TimeInterval, withStatus: TestStatus,
                        skipStatus: SkipStatus, executionCount: Int, failedExecutionCount: Int) {}
    func testGroupRetry(test: any TestRun, duration: TimeInterval, withStatus: TestStatus,
                        skipStatus: SkipStatus, executionCount: Int, failedExecutionCount: Int) -> RetryStatus?
    {
        return nil
    }
    func shouldSuppressError(test: any TestRun, skipStatus: SkipStatus,
                             executionCount: Int, failedExecutionCount: Int) -> Bool
    {
        return false
    }
}
