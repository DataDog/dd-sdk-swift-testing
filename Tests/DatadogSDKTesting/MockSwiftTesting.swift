/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogSDKTesting

extension Mocks {
    struct STTestActions: DatadogSwiftTestingTestActions {
        func cancel(reason: String, location: SwiftTestingSourceLocation) throws {
            throw STSkipError(reason: reason)
        }
        func fail(reason: String, location: SwiftTestingSourceLocation) {}
    }
    
    struct STSuite: SwiftTestingTestInfoType {
        let name: String
        let module: String
        var suite: String { name }
        let isParameterized: Bool = false
        let isSuite: Bool = true
        let hasSuite: Bool = false
    }
    
    struct STTest: SwiftTestingTestInfoType {
        let name: String
        let module: String
        let suite: String
        let isParameterized: Bool = false
        let isSuite: Bool = false
        let hasSuite: Bool = true
    }
    
    struct STTestRun: SwiftTestingTestRunInfoType {
        let name: String
        let module: String
        let suite: String
        let isParameterized: Bool = false
        let isSuite: Bool = false
        let hasSuite: Bool = true
        let parameters: TestRunParameters = .init(arguments: .nil, metadata: .nil)
        let location: SwiftTestingSourceLocation = .init(fileID: "", filePath: "",
                                                         line: 0, column: 0)
    }
    
    struct STSkipError: Error {
        let reason: String
        var isSwiftTestingSkip: Bool { true }
    }
    
    final class STRunner {
        typealias Tests = Runner.Tests
        
        private var _features: any TestHooksFeatures
        
        var tests: Tests
        var features: any TestHooksFeatures {
            get { _features }
            set { _features = STHookFeaturesProxy(wrapped: newValue) }
        }
        
        init(features: [any TestHooksFeature], tests: Tests = [:]) {
            self.tests = tests
            self._features = STHookFeaturesProxy(wrapped: features)
        }
        
        func run() async throws -> Session {
            let unskippable = tests.map { module in
                let suites = module.value.map { suite in
                    let tests = Dictionary(uniqueKeysWithValues: suite.value.map { ($0.key, $0.value.unskippable) })
                    return (suite.key, (false, tests))
                }
                return (module.key, Dictionary(uniqueKeysWithValues: suites))
            }
            
            let session = Mocks.Session.Provider(unskippable: Dictionary(uniqueKeysWithValues: unskippable))
            let manager = SessionManager(provider: session,
                                         config: .init(activeFeatures: features,
                                                       platform: DDTestMonitor.env.platform,
                                                       clock: DateClock(),
                                                       crash: nil,
                                                       command: "test command",
                                                       service: "test-runner",
                                                       metrics: [:],
                                                       log: Mocks.CatchLogger(isDebug: false)),
                                         observer: SessionAndModuleObserver())
            let suiteProvider = SwiftTestingSuiteProvider(session: manager,
                                                          observer: SwiftTestingObserver())
            let scopeProvider = DatadogSwiftTestingScopeProvider(provider: suiteProvider,
                                                                 actions: STTestActions())
            // preregister tests inside registry
            for module in tests {
                for suite in module.value {
                    for test in suite.value {
                        try await suiteProvider.registry.register(test: STTest(name: test.key,
                                                                               module: module.key,
                                                                               suite: suite.key))
                    }
                }
            }
            
            // execute tests
            for module in tests {
                try await _run(provider: scopeProvider, module: module.key, suites: module.value)
            }
            
            return session.session!
        }
        
        private func _run(provider: DatadogSwiftTestingScopeProvider,
                          module: String,
                          suites: KeyValuePairs<String, KeyValuePairs<String, Runner.TestMethod>>) async throws
        {
            for suite in suites {
                try await provider.provideScope(suite: STSuite(name: suite.key, module: module)) {
                    try await self._run(provider: provider, module: module, suite: suite.key, tests: suite.value)
                }
            }
        }
        
        private func _run(provider: DatadogSwiftTestingScopeProvider,
                          module: String, suite: String,
                          tests: KeyValuePairs<String, Runner.TestMethod>) async throws
        {
            for test in tests {
                try await provider.provideScope(test: STTest(name: test.key, module: module, suite: suite)) {
                    try await provider.provideScope(run: STTestRun(name: test.key, module: module, suite: suite)) {
                        if let duration = test.value.duration {
                            let test = Mocks.Test.active as! Mocks.Test
                            test.duration = duration.toNanoseconds
                        }
                        switch test.value.method() {
                        case .fail(let err): throw err
                        case .skip(let reason): throw STSkipError(reason: reason)
                        case .pass: break
                        }
                    }
                }
            }
        }
    }
    
    struct STHookFeaturesProxy: TestHooksFeatures {
        let wrapped: any TestHooksFeatures
        private let _configs: Synced<[String: RetryGroupConfiguration]> = .init([:])
        
        var features: [any TestHooksFeature] { wrapped.features }
        
        func testSessionWillStart(session: any TestSession) {
            wrapped.testSessionWillStart(session: session)
        }
        
        func testSessionWillEnd(session: any TestSession) {
            wrapped.testSessionWillEnd(session: session)
        }
        
        func testSessionDidEnd(session: any TestSession) {
            wrapped.testSessionDidEnd(session: session)
        }
        
        func testModuleWillStart(module: any TestModule) {
            wrapped.testModuleWillStart(module: module)
        }
        
        func testModuleWillEnd(module: any TestModule) {
            wrapped.testModuleWillEnd(module: module)
        }
        
        func testModuleDidEnd(module: any TestModule) {
            wrapped.testModuleDidEnd(module: module)
        }
        
        func testSuiteWillStart(suite: any TestSuite, testsCount: UInt) {
            wrapped.testSuiteWillStart(suite: suite, testsCount: testsCount)
        }
        
        func testSuiteWillEnd(suite: any TestSuite) {
            wrapped.testSuiteWillEnd(suite: suite)
        }
        
        func testSuiteDidEnd(suite: any DatadogSDKTesting.TestSuite) {
            wrapped.testSuiteDidEnd(suite: suite)
        }
        
        func testGroupConfiguration(
            for test: String, meta: any UnskippableMethodCheckerFactory,
            in suite: any TestSuite, configuration: RetryGroupConfiguration.Iterator
        ) -> (feature: (any TestHooksFeature)?, configuration: RetryGroupConfiguration) {
            let config = wrapped.testGroupConfiguration(for: test, meta: meta,
                                                        in: suite, configuration: configuration)
            _configs.update {
                $0[suite.name + "." + test] = config.configuration
            }
            return config
        }
        
        func testGroupWillStart(for test: String, in suite: any TestSuite) {
            wrapped.testGroupWillStart(for: test, in: suite)
        }
        
        func testWillStart(test: any TestRun, info: TestRunInfoStart) {
            if let test = test as? Mocks.Test, let group = test._group {
                let config = _configs.update { state in
                    let name = test.suite.name + "." + test.name
                    defer { state[name] = nil }
                    return state[name]
                }
                if let config {
                    group.skipStrategy = config.skipStrategy
                    group.successStrategy = config.successStrategy
                }
            }
            wrapped.testWillStart(test: test, info: info)
        }
        
        func testGroupRetry(
            test: any TestRun, duration: TimeInterval, withStatus status: TestStatus,
            andInfo info: TestRunInfoStart, retryStatus retry: RetryStatus.Iterator
        ) -> (feature: (any TestHooksFeature)?, retryStatus: RetryStatus) {
            let duration = test.duration > 0 ? .fromNanoseconds(Int64(test.duration)) : duration
            let (feature, status) = wrapped.testGroupRetry(test: test, duration: duration,
                                                           withStatus: status, andInfo: info,
                                                           retryStatus: retry)
            if let test = test as? Mocks.Test, !status.ignoreErrors {
                test.errorStatus = .unsuppressed(by: feature?.id ?? .notFeature)
            }
            return (feature, status)
        }
        
        func shouldSuppressError(test: any TestRun, info: TestRunInfoStart) -> (any TestHooksFeature)? {
            let feature = wrapped.shouldSuppressError(test: test, info: info)
            if let test = test as? Mocks.Test, !test.errorStatus.isSuppressed, let feature {
                test.errorStatus = .suppressed(by: feature.id)
            }
            return feature
        }
        
        func testWillFinish(test: any TestRun, duration: TimeInterval,
                            withStatus status: TestStatus, andInfo info: TestRunInfoEnd)
        {
            let duration = test.duration > 0 ? .fromNanoseconds(Int64(test.duration)) : duration
            wrapped.testWillFinish(test: test, duration: duration, withStatus: status, andInfo: info)
        }
        
        func testDidFinish(test: any TestRun, info: TestRunInfoEnd) {
            wrapped.testDidFinish(test: test, info: info)
        }
    }
}
