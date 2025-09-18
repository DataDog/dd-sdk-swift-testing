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
    /// Configuration for retry group. Feature can interrupt iteration or send it to the next feature with updated config.
    func testGroupConfiguration(for test: String, meta: UnskippableMethodCheckerFactory,
                                in suite: any TestSuite,
                                configuration: RetryGroupConfiguration.Iterator) -> RetryGroupConfiguration.Iterator
    /// Called for the each test run in the group.
    /// First test run will have nil info.retry. Retries will have feature id and errors status.
    /// info.executions.total and info.executions.failed don't have the current run yet
    func testWillStart(test: any TestRun, info: TestRunInfoStart) -> Void
    /// Called for the first error in the test run. Feature can return `true`
    /// to suppress errors for the current run. Errors can be restored by `testGroupRetry` call.
    /// info.executions.total and info.executions.failed don't have the current run yet
    func shouldSuppressError(test: any TestRun, info: TestRunInfoStart) -> Bool
    /// Feature should return retry status or pass the decision to the next feature.
    /// info.executions.total and info.executions.failed don't have the current run yet
    func testGroupRetry(test: any TestRun, duration: TimeInterval,
                        withStatus: TestStatus, retryStatus: RetryStatus.Iterator,
                        andInfo: TestRunInfoStart) -> RetryStatus.Iterator
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

enum RetryGroupConfiguration: Equatable, Hashable {
    struct Configuration: Equatable, Hashable {
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
    }
    
    case skip(Configuration)
    case retry(Configuration)
    
    var configuration: Configuration {
        switch self {
        case .skip(let config): return config
        case .retry(let config): return config
        }
    }
    
    var isSkip: Bool {
        switch self {
        case .skip: return true
        default: return false
        }
    }
    
    var isRetry: Bool {
        switch self {
        case .retry: return true
        default: return false
        }
    }
    
    var skipStatus: SkipStatus { configuration.skipStatus }
    var skipStrategy: RetryGroupSkipStrategy { configuration.skipStrategy }
    var successStrategy: RetryGroupSuccessStrategy { configuration.successStrategy }
}

extension RetryGroupConfiguration {
    enum Iterator {
        /// Pass configuration decision to the next feature and update configuration if needed
        case next(configuration: Configuration)
        /// Stop iteration and handle configuration
        case stop(configuration: RetryGroupConfiguration)
        
        init() {
            self = .next(configuration: .init())
        }
        
        var hasNext: Bool {
            switch self {
            case .next: return true
            default: return false
            }
        }
        
        var configuration: RetryGroupConfiguration {
            switch self {
            case .next(configuration: let config): return .retry(config)
            case .stop(configuration: let config): return config
            }
        }
        
        var isSkip: Bool {
            switch self {
            case .stop(configuration: let conf): return conf.isSkip
            default: return false
            }
        }
        
        var isRetry: Bool {
            switch self {
            case .stop(configuration: let conf): return conf.isRetry
            default: return false
            }
        }
        
        var skipStatus: SkipStatus { configuration.skipStatus }
        var skipStrategy: RetryGroupSkipStrategy { configuration.skipStrategy }
        var successStrategy: RetryGroupSuccessStrategy { configuration.successStrategy }
        
        func next(skipStatus: SkipStatus? = nil,
                  skipStrategy: RetryGroupSkipStrategy? = nil,
                  successStrategy: RetryGroupSuccessStrategy? = nil) -> Self
        {
            switch self {
            case .next(configuration: let conf):
                return .next(configuration: conf.updated(skipStatus: skipStatus,
                                                         skipStrategy: skipStrategy,
                                                         successStrategy: successStrategy))
            default: return self
            }
        }
        
        func skip(status: SkipStatus, strategy skip: RetryGroupSkipStrategy) -> Self {
            switch self {
            case .next(configuration: let conf):
                return .stop(configuration: .skip(conf.updated(skipStatus: status,
                                                               skipStrategy: skip)))
            default: return self
            }
            
        }
        
        func retry(strategy success: RetryGroupSuccessStrategy) -> Self {
            switch self {
            case .next(configuration: let conf):
                return .stop(configuration: .retry(conf.updated(successStrategy: success)))
            default: return self
            }
        }
        
        func retry(softer success: RetryGroupSuccessStrategy) -> Self {
            switch self {
            case .next(configuration: let conf):
                return success < conf.successStrategy
                ? .stop(configuration: .retry(conf.updated(successStrategy: success)))
                : .stop(configuration: .retry(conf))
            default: return self
            }
        }
    }
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
    struct Configuration: Equatable, Hashable {
        // Ingore errors or record them
        let ignoreErrors: Bool
        
        init(ignoreErrors: Bool = false) {
            self.ignoreErrors = ignoreErrors
        }
        
        func updated(ignoreErrors: Bool? = nil) -> Self {
            .init(ignoreErrors: ignoreErrors ?? self.ignoreErrors)
        }
    }
    
    /// Stop retries.
    case end(Configuration)
    
    /// Retry current test more.
    case retry(Configuration)
    
    var isRetry: Bool {
        switch self {
        case .retry:
            return true
        default:
            return false
        }
    }
    
    var configuration: Configuration {
        switch self {
        case .end(let conf): return conf
        case .retry(let conf): return conf
        }
    }
    
    var ignoreErrors: Bool { configuration.ignoreErrors }
}

extension RetryStatus {
    enum Iterator: Equatable, Hashable {
        /// Pass retry decision to the next feature
        case next(configuration: RetryStatus.Configuration)
        /// Stop iteration.
        case stop(status: RetryStatus)
        
        init() {
            self = .next(configuration: .init())
        }
        
        var hasNext: Bool {
            switch self {
            case .next: return true
            default: return false
            }
        }
        
        var status: RetryStatus {
            switch self {
            case .next(configuration: let config): return .end(config)
            case .stop(status: let status): return status
            }
        }
        
        func next(ignoreErrors: Bool? = nil) -> Self {
            switch self {
            case .next(configuration: let config):
                return .next(configuration: config.updated(ignoreErrors: ignoreErrors))
            default: return self
            }
        }
        
        func retry(ignoreErrors: Bool? = nil) -> Self {
            switch self {
            case .next(configuration: let config):
                return .stop(status: .retry(config.updated(ignoreErrors: ignoreErrors)))
            default: return self
            }
        }
        
        func end(ignoreErrors: Bool? = nil) -> Self {
            switch self {
            case .next(configuration: let config):
                return .stop(status: .end(config.updated(ignoreErrors: ignoreErrors)))
            default: return self
            }
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

// Default hooks implementation
extension TestHooksFeature {
    func testSuiteWillStart(suite: any TestSuite, testsCount: UInt) {}
    func testGroupWillStart(for test: String, in suite: any TestSuite) {}
    func testGroupConfiguration(for test: String, meta: UnskippableMethodCheckerFactory,
                                in suite: any TestSuite,
                                configuration: RetryGroupConfiguration.Iterator) -> RetryGroupConfiguration.Iterator
    {
        return configuration.next()
    }
    func testWillStart(test: any TestRun, info: TestRunInfoStart) {}
    func testGroupRetry(test: any TestRun, duration: TimeInterval,
                        withStatus: TestStatus, retryStatus: RetryStatus.Iterator,
                        andInfo: TestRunInfoStart) -> RetryStatus.Iterator
    {
        return retryStatus.next()
    }
    func shouldSuppressError(test: any TestRun, info: TestRunInfoStart) -> Bool
    {
        return false
    }
    func testWillFinish(test: any TestRun, duration: TimeInterval, withStatus: TestStatus,
                        andInfo: TestRunInfoEnd) {}
    func testDidFinish(test: any TestRun, info: TestRunInfoEnd) {}
}


// Iteration helpers for hooks
extension Array where Element == (any TestHooksFeature) {
    func testSuiteWillStart(suite: any TestSuite, testsCount: UInt) {
        for feature in self {
            feature.testSuiteWillStart(suite: suite, testsCount: testsCount)
        }
    }
    
    func testGroupWillStart(for test: String, in suite: any TestSuite) {
        for feature in self {
            feature.testGroupWillStart(for: test, in: suite)
        }
    }
    
    func testGroupConfiguration(
        for test: String, meta: UnskippableMethodCheckerFactory, in suite: any TestSuite,
        configuration: RetryGroupConfiguration.Iterator = .init()
    ) -> (feature: (any TestHooksFeature)?, configuration: RetryGroupConfiguration) {
        var configuration = configuration
        for feature in self {
            configuration = feature.testGroupConfiguration(
                for: test,
                meta: meta,
                in: suite,
                configuration: configuration
            )
            if !configuration.hasNext {
                return (feature, configuration.configuration)
            }
        }
        return (nil, configuration.configuration)
    }
    
    func testWillStart(test: any TestRun, info: TestRunInfoStart) {
        for feature in self {
            feature.testWillStart(test: test, info: info)
        }
    }
    
    func shouldSuppressError(test: any TestRun, info: TestRunInfoStart) -> (any TestHooksFeature)? {
        for feature in self {
            if feature.shouldSuppressError(test: test, info: info) {
                return feature
            }
        }
        return nil
    }
    
    func testGroupRetry(
        test: any TestRun, duration: TimeInterval,
        withStatus status: TestStatus, andInfo info: TestRunInfoStart,
        retryStatus retry: RetryStatus.Iterator = .init()
    ) -> (feature: (any TestHooksFeature)?, retryStatus: RetryStatus) {
        var retry = retry
        for feature in self {
            retry = feature.testGroupRetry(test: test, duration: duration,
                                           withStatus: status, retryStatus: retry, andInfo: info)
            if !retry.hasNext {
                return (feature, retry.status)
            }
        }
        return (nil, retry.status)
    }
    
    func testWillFinish(test: any TestRun, duration: TimeInterval,
                        withStatus status: TestStatus, andInfo info: TestRunInfoEnd)
    {
        for feature in self {
            feature.testWillFinish(test: test, duration: duration, withStatus: status, andInfo: info)
        }
    }
    
    func testDidFinish(test: any TestRun, info: TestRunInfoEnd) {
        for feature in self {
            feature.testDidFinish(test: test, info: info)
        }
    }
}
