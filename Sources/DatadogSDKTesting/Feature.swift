/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import EventsExporter

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
    // Configuration for retry group. Will use first not nil
    func testGroupConfiguration(for test: String, meta: UnskippableMethodOwner.Type,
                                in suite: any TestSuite) -> TestRetryGroupConfiguration?
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
    case skip(status: SkipStatus, strategy: RetryGroupSkipStrategy)
    case retry(success: RetryGroupSuccessStrategy)
    
    var skipStatus: SkipStatus {
        switch self {
        case .skip(status: let status, strategy: _): return status
        default: return Optional<Self>.none.skipStatus
        }
    }
    
    var successStrategy: RetryGroupSuccessStrategy {
        switch self {
        case .retry(success: let strategy): return strategy
        default: return Optional<Self>.none.successStrategy
        }
    }
    
    var skipStrategy: RetryGroupSkipStrategy {
        switch self {
        case .skip(status: _, strategy: let strategy): return strategy
        default: return Optional<Self>.none.skipStrategy
        }
    }
}

extension Optional where Wrapped == TestRetryGroupConfiguration {
    var successStrategy: RetryGroupSuccessStrategy {
        switch self {
        case .none: return .allSucceeded
        case .some(let s): return s.successStrategy
        }
    }
    var skipStrategy: RetryGroupSkipStrategy {
        switch self {
        case .none: return .allSkipped
        case .some(let s): return s.skipStrategy
        }
    }
    var skipStatus: SkipStatus {
        switch self {
        case .none: return .normalRun
        case .some(let s): return s.skipStatus
        }
    }
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
    func testGroupConfiguration(for test: String, meta: UnskippableMethodOwner.Type,
                                in suite: any TestSuite) -> TestRetryGroupConfiguration?
    {
        return nil
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
