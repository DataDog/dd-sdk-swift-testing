/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogSDKTesting

extension Mocks {
    class Runner {
        enum TestResult {
            case pass
            case fail(TestError)
            case skip(String)
            
            var status: TestStatus {
                switch self {
                case .fail(_): return .fail
                case .pass: return .pass
                case .skip(_): return .skip
                }
            }
        }
        
        struct TestMethod {
            let duration: TimeInterval?
            let unskippable: Bool
            let method: () -> TestResult
            
            init(duration: TimeInterval? = nil, unskippable: Bool = false, method: @escaping () -> TestResult) {
                self.method = method
                self.duration = duration
                self.unskippable = unskippable
            }
            
            static func withState<State>(_ initial: State, duration: TimeInterval? = nil, unskippable: Bool = false, method: @escaping (inout State) -> TestResult) -> Self {
                var state = initial
                return TestMethod(duration: duration, unskippable: unskippable) { method(&state) }
            }
            
            static func runCounter<State>(_ initial: State, duration: TimeInterval? = nil, unskippable: Bool = false, method: @escaping (UInt, inout State) -> TestResult) -> Self {
                withState((UInt(0), initial), duration: duration, unskippable: unskippable) { state in
                    defer { state.0 += 1 }
                    return method(state.0, &state.1)
                }
            }
            
            static func failOddRuns(_ duration: TimeInterval? = nil, unskippable: Bool = false) -> Self {
                runCounter((), duration: duration, unskippable: unskippable) { (count, _) in
                    (count+1).isMultiple(of: 2) ? .pass : .fail(.init(type: "Odd Runs Should Fail"))
                }
            }
            
            static func failEvenRuns(_ duration: TimeInterval? = nil, unskippable: Bool = false) -> Self {
                runCounter((), duration: duration, unskippable: unskippable) { (count, _) in
                    (count+1).isMultiple(of: 2) ? .fail(.init(type: "Even Runs Should Fail")) : .pass
                }
            }
            
            static func fail(first: Int, _ duration: TimeInterval? = nil, unskippable: Bool = false) -> Self {
                runCounter((), duration: duration, unskippable: unskippable) { (count, _) in
                    count < first ? .fail(.init(type: "Fail \(count+1) from \(first)")) : .pass
                }
            }
            
            static func fail(after: Int, _ duration: TimeInterval? = nil, unskippable: Bool = false) -> Self {
                runCounter((), duration: duration, unskippable: unskippable) { (count, _) in
                    count+1 >= after ? .fail(.init(type: "Fail \(Int(count)+2-after) after \(after)")) : .pass
                }
            }
            
            static func skip(_ reason: String, unskippable: Bool = false) -> Self {
                TestMethod(duration: 0.0001, unskippable: unskippable) { .skip(reason) }
            }
            
            static func pass(_ duration: TimeInterval? = nil, unskippable: Bool = false) -> Self {
                TestMethod(duration: duration, unskippable: unskippable) { .pass }
            }
            
            static func fail(_ reason: String, duration: TimeInterval? = nil, unskippable: Bool = false) -> Self {
                TestMethod(duration: duration, unskippable: unskippable) { .fail(.init(type: reason)) }
            }
        }
        
        // Module, Suite, Test, [Runs]
        typealias Tests = KeyValuePairs<String, KeyValuePairs<String, KeyValuePairs<String, TestMethod>>>
        
        var tests: Tests
        var features: any TestHooksFeatures
        
        init(features: [any TestHooksFeature], tests: Tests = [:]) {
            self.tests = tests
            self.features = features
        }
        
        func run() async -> Session {
            let unskippable = tests.map { module in
                let suites = module.value.map { suite in
                    let tests = Dictionary(uniqueKeysWithValues: suite.value.map { ($0.key, $0.value.unskippable) })
                    return (suite.key, (false, tests))
                }
                return (module.key, Dictionary(uniqueKeysWithValues: suites))
            }
            let observer = SessionAndModuleObserver()
            let config = SessionConfig(activeFeatures: features,
                                       platform: DDTestMonitor.env.platform,
                                       clock: DateClock(),
                                       crash: nil,
                                       command: "test command",
                                       service: "test-runner",
                                       metrics: [:],
                                       log: Mocks.CatchLogger(isDebug: false))
            let session = Session(name: "MockTestSession",
                                  unskippable: Dictionary(uniqueKeysWithValues: unskippable),
                                  config: config,
                                  observer: observer)
            await observer.didStart(session: session, with: config)
            for (module, suites) in tests {
                _run(module: module, suites: suites, session: session)
            }
            await observer.willFinish(session: session, with: config)
            session.end()
            await observer.didFinish(session: session, with: config)
            return session
        }
        
        func _run(module name: String, suites: KeyValuePairs<String, KeyValuePairs<String, TestMethod>>, session: Session) {
            let module = session.module(named: name) as! Mocks.Module
            for (suite, tests) in suites {
                _run(suite: suite, tests: tests, module: module)
            }
            if let config = session._sessionConfig {
                session._moduleObserver?.willFinish(module: module, with: config)
            }
            session.end(module: module)
            if let config = session._sessionConfig {
                session._moduleObserver?.didFinish(module: module, with: config)
            }
        }
        
        func _run(suite name: String, tests: KeyValuePairs<String, TestMethod>, module: Module) {
            let suite = module.startSuite(named: name, at: nil, framework: "MockRunner") as! Mocks.Suite
            features.testSuiteWillStart(suite: suite, testsCount: UInt(tests.count))
            for (test, method) in tests {
                _run(group: test, method: method, suite: suite)
            }
            features.testSuiteWillEnd(suite: suite)
            suite.end()
            features.testSuiteDidEnd(suite: suite)
        }
        
        func _run(group name: String, method: TestMethod, suite: Suite) {
            let group = suite.startGroup(named: name)
            
            let (feature, config) = features.testGroupConfiguration(for: group.name, meta: group, in: suite)
            
            group.skipStrategy = config.skipStrategy
            group.successStrategy = config.successStrategy
            
            features.testGroupWillStart(for: group.name, in: suite)
            
            var skip: (by: (feature: FeatureId, reason: String)?, status: SkipStatus) = (nil, config.skipStatus)
            if let feature = feature, case .skip(reason: let reason, _) = config {
                skip.by = (feature.id, reason)
            }
            
            var info = TestRunInfoEnd(skip: skip,
                                      retry: (nil, .end(errors: .unsuppressed)),
                                      executions: (0, 0))
            
            if let by = skip.by {
                info = _run(test: name, method: .skip(by.reason), info: info.startInfo, group: group)
            } else {
                info = _run(test: name, method: method, info: info.startInfo, group: group)
            }
            
            while info.retry.status.isRetry {
                info = _run(test: name, method: method, info: info.startInfo, group: group)
            }
        }
        
        func _run(test name: String, method: TestMethod, info: TestRunInfoStart, group: Group) -> TestRunInfoEnd {
            var (test, endInfo) = group.withTest(named: name) { test in
                var info = info
                
                features.testWillStart(test: test, info: info)
                
                let result = method.method()
                let duration = method.duration ?? (Date().timeIntervalSince(test.startTime))
                
                switch result {
                case .fail(let testError):
                    test.add(error: testError)
                    if !test.errorStatus.isSuppressed,
                       let feature = features.shouldSuppressError(test: test, info: info)
                    {
                        test.errorStatus = .suppressed(by: feature.id)
                    }
                case .skip(let reason):
                    // we have skipped from code
                    if info.skip.by == nil {
                        info = TestRunInfoStart(skip: (by: (feature: .notFeature,
                                                            reason: reason),
                                                       status: info.skip.status),
                                                retry: info.retry,
                                                executions: info.executions)
                    }
                default: break
                }
                
                let (feature, retryStatus) = features.testGroupRetry(test: test, duration: duration,
                                                                     withStatus: result.status, andInfo: info)
                
                if !retryStatus.ignoreErrors {
                    test.errorStatus = .unsuppressed(by: feature?.id ?? .notFeature)
                }
                
                // update info with the new retry
                let endInfo = TestRunInfoEnd(skip: info.skip,
                                             retry: (feature: feature?.id,
                                                     status: retryStatus),
                                             executions: info.executions)
                features.testWillFinish(test: test, duration: duration, withStatus: result.status, andInfo: endInfo)
                
                test.set(status: result.status)
                test.end(time: test.startTime.addingTimeInterval(duration))
                
                return (test, endInfo)
            }
            
            // update info with the new run counts
            endInfo = TestRunInfoEnd(skip: endInfo.skip,
                                     retry: endInfo.retry,
                                     executions: (group.executionCount, group.failedExecutionCount))
            features.testDidFinish(test: test, info: endInfo)
            
            return endInfo
        }
    }
}

extension TestRunInfoEnd {
    var startInfo: TestRunInfoStart {
        .init(skip: skip,
              retry: retry.feature.flatMap { id in retry.status.retryReason.map { (id, $0) } }.map {
                  (feature: $0, reason: $1, errors: retry.status.errorsStatus)
              },
              executions: executions)
    }
}
