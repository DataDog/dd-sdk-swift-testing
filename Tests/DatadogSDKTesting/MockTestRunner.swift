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
        
        struct TestSuite: ExpressibleByDictionaryLiteral {
            typealias Key = String
            typealias Value = TestMethod
            
            let tests: [(name: String, method: TestMethod)]
            let tags: AttachedTags
            
            init(tests: [(name: String, method: TestMethod)], tags: AttachedTags = .init()) {
                self.tests = tests
                self.tags = tags
            }
            
            init(tests: KeyValuePairs<String, TestMethod>, tags: AttachedTags = .init()) {
                self.init(tests: tests.map { ($0.key, $0.value) }, tags: tags)
            }
            
            init(dictionaryLiteral elements: (String, Mocks.Runner.TestMethod)...) {
                self.init(tests: elements)
            }
        }
        
        struct TestMethod {
            let duration: TimeInterval?
            let tags: AttachedTags
            let method: () -> TestResult
            
            init(duration: TimeInterval? = nil, tags: AttachedTags = .init(), method: @escaping () -> TestResult) {
                self.method = method
                self.duration = duration
                self.tags = tags
            }
            
            static func withState<State>(_ initial: State, duration: TimeInterval? = nil, tags: AttachedTags = .init(),
                                         method: @escaping (inout State) -> TestResult) -> Self
            {
                var state = initial
                return TestMethod(duration: duration, tags: tags) { method(&state) }
            }
            
            static func runCounter<State>(_ initial: State, duration: TimeInterval? = nil, tags: AttachedTags = .init(),
                                          method: @escaping (UInt, inout State) -> TestResult) -> Self
            {
                withState((UInt(0), initial), duration: duration, tags: tags) { state in
                    defer { state.0 += 1 }
                    return method(state.0, &state.1)
                }
            }
            
            static func failOddRuns(_ duration: TimeInterval? = nil, tags: AttachedTags = .init()) -> Self {
                runCounter((), duration: duration, tags: tags) { (count, _) in
                    (count+1).isMultiple(of: 2) ? .pass : .fail(.init(type: "Odd Runs Should Fail"))
                }
            }
            
            static func failEvenRuns(_ duration: TimeInterval? = nil, tags: AttachedTags = .init()) -> Self {
                runCounter((), duration: duration, tags: tags) { (count, _) in
                    (count+1).isMultiple(of: 2) ? .fail(.init(type: "Even Runs Should Fail")) : .pass
                }
            }
            
            static func fail(first: Int, _ duration: TimeInterval? = nil, tags: AttachedTags = .init()) -> Self {
                runCounter((), duration: duration, tags: tags) { (count, _) in
                    count < first ? .fail(.init(type: "Fail \(count+1) from \(first)")) : .pass
                }
            }
            
            static func fail(after: Int, _ duration: TimeInterval? = nil, tags: AttachedTags = .init()) -> Self {
                runCounter((), duration: duration, tags: tags) { (count, _) in
                    count+1 >= after ? .fail(.init(type: "Fail \(Int(count)+2-after) after \(after)")) : .pass
                }
            }
            
            static func skip(_ reason: String, tags: AttachedTags = .init()) -> Self {
                TestMethod(duration: 0.0001, tags: tags) { .skip(reason) }
            }
            
            static func pass(_ duration: TimeInterval? = nil, tags: AttachedTags = .init()) -> Self {
                TestMethod(duration: duration, tags: tags) { .pass }
            }
            
            static func fail(_ reason: String, duration: TimeInterval? = nil, tags: AttachedTags = .init()) -> Self {
                TestMethod(duration: duration, tags: tags) { .fail(.init(type: reason)) }
            }
        }
        
        struct CombinedTags: TestTags {
            let suite: any TestTags
            let test: any TestTags
            
            func get<T: TestTag>(tag: T) -> T.Value? {
                test.get(tag: tag) ?? suite.get(tag: tag)
            }
        }
        
        // Module, Suite, Test, [Runs]
        typealias Tests = KeyValuePairs<String, KeyValuePairs<String, TestSuite>>
        
        var tests: Tests
        var features: any TestHooksFeatures
        
        init(features: [any TestHooksFeature], tests: Tests = [:]) {
            self.tests = tests
            self.features = features
        }
        
        func run() async -> Session {
            let tags = tests.map { module in
                let suites = module.value.map { suite in
                    let tests = Dictionary(uniqueKeysWithValues: suite.value.tests.map { ($0.name, $0.method.tags) })
                    return (suite.key, (suite.value.tags, tests))
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
                                  testTags: Dictionary(uniqueKeysWithValues: tags),
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
        
        func _run(module name: String, suites: KeyValuePairs<String, TestSuite>, session: Session) {
            let module = session.module(named: name) as! Mocks.Module
            for (name, info) in suites {
                _run(suite: name, info: info, module: module)
            }
            if let config = session._sessionConfig {
                session._moduleObserver?.willFinish(module: module, with: config)
            }
            session.end(module: module)
            if let config = session._sessionConfig {
                session._moduleObserver?.didFinish(module: module, with: config)
            }
        }
        
        func _run(suite name: String, info: TestSuite, module: Module) {
            let suite = module.startSuite(named: name, at: nil, framework: .init(name: "MockRunner", version: "1.0.0")) as! Mocks.Suite
            features.testSuiteWillStart(suite: suite, testsCount: UInt(info.tests.count))
            for (test, method) in info.tests {
                _run(group: test, method: method, suite: suite)
            }
            features.testSuiteWillEnd(suite: suite)
            suite.end()
            features.testSuiteDidEnd(suite: suite)
        }
        
        func _run(group name: String, method: TestMethod, suite: Suite) {
            let group = suite.startGroup(named: name)
            let tags = CombinedTags(suite: suite.attachedTags, test: group.attachedTags)
        
            let (feature, config) = features.testGroupConfiguration(for: group.name, tags: tags, in: suite)
            
            group.skipStrategy = config.skipStrategy
            group.successStrategy = config.successStrategy
            
            features.testGroupWillStart(for: group.name, in: suite)
            
            var skip: (by: (feature: FeatureId, reason: String)?, status: SkipStatus) = (nil, config.skipStatus)
            if let feature = feature, case .skip(reason: let reason, _) = config {
                skip.by = (feature.id, reason)
            }
            
            var info = TestRunInfoEnd(tags: tags,
                                      skip: skip,
                                      retry: (nil, .end(errors: .unsuppressed)),
                                      executions: (0, 0))
            
            if let by = skip.by {
                info = _run(test: name, method: .skip(by.reason), info: info.toStart, group: group)
            } else {
                info = _run(test: name, method: method, info: info.toStart, group: group)
            }
            
            while info.retry.status.isRetry {
                info = _run(test: name, method: method, info: info.toStart, group: group)
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
                        info.skip = (by: (feature: .notFeature,
                                          reason: reason),
                                     status: info.skip.status)
                    }
                default: break
                }
                
                let (feature, retryStatus) = features.testGroupRetry(test: test, duration: duration,
                                                                     withStatus: result.status, andInfo: info)
                
                if !retryStatus.ignoreErrors {
                    test.errorStatus = .unsuppressed(by: feature?.id ?? .notFeature)
                }
                
                // update info with the new retry
                let endInfo = TestRunInfoEnd(tags: info.tags,
                                             skip: info.skip,
                                             retry: (feature: feature?.id,
                                                     status: retryStatus),
                                             executions: info.executions)
                features.testWillFinish(test: test, duration: duration, withStatus: result.status, andInfo: endInfo)
                
                test.set(status: result.status)
                test.end(time: test.startTime.addingTimeInterval(duration))
                
                return (test, endInfo)
            }
            
            // update info with the new run counts
            endInfo.executions = (group.executionCount, group.failedExecutionCount)
            
            features.testDidFinish(test: test, info: endInfo)
            
            return endInfo
        }
    }
}
