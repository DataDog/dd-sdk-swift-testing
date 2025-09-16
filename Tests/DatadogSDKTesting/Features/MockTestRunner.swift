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
        var features: [any TestHooksFeature]
        
        init(features: [any TestHooksFeature], tests: Tests = [:]) {
            self.tests = tests
            self.features = features
        }
        
        func run() -> Session {
            let session = Session(name: "MockTestSession")
            for (module, suites) in tests {
                let mod = _run(module: module, suites: suites, session: session)
                session.add(module: mod)
            }
            return session
        }
        
        func _run(module name: String, suites: KeyValuePairs<String, KeyValuePairs<String, TestMethod>>, session: Session) -> Module {
            let module = Module(name: name, session: session)
            for (suite, tests) in suites {
                let st = _run(suite: suite, tests: tests, module: module)
                module.add(suite: st)
            }
            module.end()
            return module
        }
        
        func _run(suite name: String, tests: KeyValuePairs<String, TestMethod>, module: Module) -> Suite {
            let suite = Suite(name: name, module: module)
            features.forEach { $0.testSuiteWillStart(suite: suite, testsCount: UInt(tests.count)) }
            for (test, method) in tests {
                let group = _run(group: test, method: method, suite: suite)
                suite.add(group: group)
            }
            suite.end()
            return suite
        }
        
        func _run(group name: String, method: TestMethod, suite: Suite) -> Group {
            let group = Group(name: name, suite: suite, unskippable: method.unskippable)
            
            let (config, featureId) = features.reduce((TestRetryGroupConfiguration.next(.init()), "")) { prev, feature in
                guard prev.0.hasNext else { return prev }
                let next = feature.testGroupConfiguration(for: group.name, meta: group,
                                                          in: suite, configuration: prev.0.configuration)
                return (next, feature.id)
            }
            
            group.skipStrategy = config.skipStrategy
            group.successStrategy = config.successStrategy
            
            features.forEach { $0.testGroupWillStart(for: group.name, in: suite) }
            
            let skipStatus = config.skipStatus
            var info = TestRunInfoEnd(skip: skipStatus,
                                      retry: (nil, .end(ignoreErrors: false)),
                                      executions: (0, 0))
            
            if skipStatus.isSkipped {
                info = _run(test: name, method: .skip(featureId), info: info.startInfo, group: group)
            } else {
                info = _run(test: name, method: method, info: info.startInfo, group: group)
            }
            
            while info.retry.status.isRetry {
                info = _run(test: name, method: method, info: info.startInfo, group: group)
            }
            
            return group
        }
        
        func _run(test name: String, method: TestMethod, info: TestRunInfoStart, group: Group) -> TestRunInfoEnd {
            let test = Test(name: name, suite: group.suite)
            // To emulate how XCTest work. It's added before execution
            // Group simply ignores it's results till it finished
            group.add(run: test)
            
            for feature in features {
                feature.testWillStart(test: test, info: info)
            }
            
            let result = method.method()
            let duration = method.duration ?? (Date().timeIntervalSince(test.startTime))
            
            if case .fail(let testError) = result {
                test.add(error: testError)
                
                let suppress = features.reduce((false, "")) { prev, feature in
                    guard !prev.0 else { return prev }
                    let suppress =  feature.shouldSuppressError(test: test, info: info)
                    return (suppress, feature.id)
                }
                
                if suppress.0 {
                    test.errorStatus = .suppressed
                }
            }
            
            
            let actionAndFeature: (RetryStatusIterator, String) = features.reduce((.init(), "")) { prev, feature in
                guard prev.0.hasNext else { return prev }
                let next = feature.testGroupRetry(test: test, duration: duration, withStatus: result.status,
                                                  iterator: prev.0, andInfo: info)
                return (next, feature.id)
            }
            
            if !actionAndFeature.0.status.ignoreErrors {
                test.errorStatus = .unsuppressed
            }
            
            let retryInfo = actionAndFeature.0.hasNext
                ? (reason: nil, status: actionAndFeature.0.status)
                : (reason: actionAndFeature.1, status: actionAndFeature.0.status)
            
            // update info with the new retry
            var endInfo = TestRunInfoEnd(skip: info.skip,
                                         retry: retryInfo,
                                         executions: info.executions)
            
            for feature in features {
                feature.testWillFinish(test: test, duration: duration, withStatus: result.status, andInfo: endInfo)
            }
            test.end(status: result.status, time: test.startTime.addingTimeInterval(duration))
            
            
            // update info with the new run counts
            endInfo = TestRunInfoEnd(skip: endInfo.skip,
                                     retry: endInfo.retry,
                                     executions: (group.executionCount, group.failedExecutionCount))
            for feature in features {
                feature.testDidFinish(test: test, info: endInfo)
            }
            
            return endInfo
        }
    }
}

extension TestRunInfoEnd {
    var startInfo: TestRunInfoStart {
        .init(skip: skip,
              retry: retry.reason.map { ($0, retry.status.ignoreErrors) },
              executions: executions)
    }
}
