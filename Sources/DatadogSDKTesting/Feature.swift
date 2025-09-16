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
    /// Start of the suite
    func testSuiteWillStart(suite: any TestSuite, testsCount: UInt) -> Void
    /// Start of the test case
    func testGroupWillStart(for test: String, in suite: any TestSuite) -> Void
    /// Configuration for retry group. Will use the first which is not .next
    func testGroupConfiguration(for test: String, meta: UnskippableMethodCheckerFactory,
                                in suite: any TestSuite,
                                configuration: TestRetryGroupConfiguration.Configuration) -> TestRetryGroupConfiguration
    /// Called for the each test run in the group.
    /// First test run will have nil info.retry. Retries will have feature id and errors status.
    /// info.executions.total and info.executions.failed don't have the current run yet
    func testWillStart(test: any TestRun, info: TestRunInfoStart) -> Void
    /// Called for the first error in the test run. Feature can return `true`
    /// to suppress errors for the current run. Errors can be restored by `testGroupRetry` call.
    /// info.executions.total and info.executions.failed don't have the current run yet
    func shouldSuppressError(test: any TestRun, info: TestRunInfoStart) -> Bool
    /// Feature could return retry status. First non nil one will be used
    /// info.executions.total and info.executions.failed don't have the current run yet
    func testGroupRetry(test: any TestRun, duration: TimeInterval,
                        withStatus: TestStatus, iterator: RetryStatusIterator,
                        andInfo: TestRunInfoStart) -> RetryStatusIterator
    /// Called right before the `end()` of the TestRun to add more tags if needed.
    /// info.executions.total and info.executions.failed don't have the current run yet.
    /// info.retry has the new status returned by `testGroupRetry` call.
    func testWillFinish(test: any TestRun, duration: TimeInterval, withStatus: TestStatus,
                        andInfo: TestRunInfoEnd) -> Void
    /// Called right at the `end()` of the TestRun. Tags could not be added at this moment anymore.
    /// info.executions.total and info.executions.failed already have the current run.
    /// info.retry has the new status returned by `testGroupRetry` call.
    func testDidFinish(test: any TestRun, info: TestRunInfoEnd) -> Void
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
        
        func retry(softer success: RetryGroupSuccessStrategy) -> TestRetryGroupConfiguration {
            success < successStrategy ? .retry(updated(successStrategy: success)) : .retry(self)
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

enum RetryGroupSuccessStrategy: Equatable, Hashable, Comparable {
    // softer to stronger
    case alwaysSucceeded
    case atLeastOneSucceeded
    case atMostOneFailed
    case allSucceeded
}

enum RetryGroupSkipStrategy: Equatable, Hashable, Comparable {
    // softer to stronger
    case atLeastOneSkipped
    case allSkipped
}

struct SkipStatus: Equatable, Hashable {
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
    /// Stop retries. Ignore errors or record them.
    case end(ignoreErrors: Bool)
    
    /// Retry current test more. Ignore errors or record them.
    case retry(ignoreErrors: Bool)
    
    var isRetry: Bool {
        switch self {
        case .retry:
            return true
        default:
            return false
        }
    }
    
    var ignoreErrors: Bool {
        switch self {
        case .retry(ignoreErrors: let ignoreErrors):
            return ignoreErrors
        case .end(ignoreErrors: let ignoreErrors):
            return ignoreErrors
        }
    }
}

enum RetryStatusIterator: Equatable, Hashable {
    /// Pass retry decision to the next feature
    case next(ignoreErrors: Bool)
    /// Stop iteration.
    case stop(status: RetryStatus)
    
    init() {
        self = .next(ignoreErrors: false)
    }
    
    var hasNext: Bool {
        switch self {
        case .next: return true
        default: return false
        }
    }
    
    var status: RetryStatus {
        switch self {
        case .next(ignoreErrors: let errs):
            return .end(ignoreErrors: errs)
        case .stop(status: let status):
            return status
        }
    }
    
    func next(ignoreErrors: Bool? = nil) -> Self {
        switch self {
        case .next(ignoreErrors: let errs):
            return .next(ignoreErrors: ignoreErrors ?? errs)
        default: return self
        }
    }
    
    func retry(ignoreErrors: Bool? = nil) -> Self {
        switch self {
        case .next(ignoreErrors: let errs):
            return .stop(status: .retry(ignoreErrors: ignoreErrors ?? errs))
        default: return self
        }
    }
    
    func end(ignoreErrors: Bool? = nil) -> Self {
        switch self {
        case .next(ignoreErrors: let errs):
            return .stop(status: .end(ignoreErrors: ignoreErrors ?? errs))
        default: return self
        }
    }
}


struct TestRunInfo<RetryInfo> {
    let skip: SkipStatus
    let retry: RetryInfo
    let executions: (total: Int, failed: Int)
}

typealias TestRunInfoStart = TestRunInfo<(reason: String, errorsWasSuppressed: Bool)?>
typealias TestRunInfoEnd = TestRunInfo<(reason: String?, status: RetryStatus)>

extension TestHooksFeature {
    func testSuiteWillStart(suite: any TestSuite, testsCount: UInt) {}
    func testGroupWillStart(for test: String, in suite: any TestSuite) {}
    func testGroupConfiguration(for test: String, meta: UnskippableMethodCheckerFactory,
                                in suite: any TestSuite,
                                configuration: TestRetryGroupConfiguration.Configuration) -> TestRetryGroupConfiguration
    {
        return configuration.next()
    }
    func testWillStart(test: any TestRun, info: TestRunInfoStart) {}
    func testGroupRetry(test: any TestRun, duration: TimeInterval,
                        withStatus: TestStatus, iterator: RetryStatusIterator,
                        andInfo: TestRunInfoStart) -> RetryStatusIterator
    {
        return iterator.next()
    }
    func shouldSuppressError(test: any TestRun, info: TestRunInfoStart) -> Bool
    {
        return false
    }
    func testWillFinish(test: any TestRun, duration: TimeInterval, withStatus: TestStatus,
                        andInfo: TestRunInfoEnd) {}
    func testDidFinish(test: any TestRun, info: TestRunInfoEnd) {}
}
