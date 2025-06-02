/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogSDKTesting

extension Mocks {
    class Runner {
        struct TestResult {
            enum Result {
                case pass
                case fail(TestError)
                case skip(String)
            }
            
            var result: Result
            var duration: Double
            
            var status: TestStatus {
                switch self.result {
                case .fail(_): return .fail
                case .pass: return .pass
                case .skip(_): return .skip
                }
            }
            
            static func pass(_ duration: Double = .random(in: 0...30.535)) -> Self {
                .init(result: .pass, duration: duration)
            }
            
            static func fail(_ error: TestError, _ duration: Double = .random(in: 0...30.535)) -> Self {
                .init(result: .fail(error), duration: duration)
            }
            
            static func skip(_ reason: String, _ duration: Double = 0) -> Self {
                .init(result: .skip(reason), duration: duration)
            }
        }
        
        // Module, Suite, Test, [Runs]
        typealias Tests = [String: [String: [String: [TestResult]]]]
        
        var tests: Tests
        var features: [any TestHooksFeature]
        
        init(features: [any TestHooksFeature], tests: Tests = [:]) {
            self.tests = tests
            self.features = features
        }
        
        func add(_ result: TestResult, module: String, suite: String, test: String) {
            tests.get(key: module, or: [:]) { module in
                module.get(key: suite, or: [:]) { suite in
                    suite.get(key: test, or: []) { test in
                        test.append(result)
                    }
                }
            }
        }
        
        func run() -> Session {
            let session = Session(name: "UnitTestSession")
            for (module, suites) in tests {
                let mod = _run(module: module, suites: suites, session: session)
                session.add(module: mod)
            }
            return session
        }
        
        func _run(module name: String, suites: [String: [String: [TestResult]]], session: Session) -> Module {
            let module = Module(name: name, session: session)
            for (suite, tests) in suites {
                let st = _run(suite: suite, tests: tests, module: module)
                module.add(suite: st)
            }
            module.end()
            return module
        }
        
        func _run(suite name: String, tests: [String: [TestResult]], module: Module) -> Suite {
            let suite = Suite(name: name, module: module)
            features.forEach { $0.testSuiteWillStart(suite: suite, testsCount: UInt(tests.count)) }
            for (test, runs) in tests {
                let group = _run(group: test, runs: runs, suite: suite)
                suite.add(group: group)
            }
            suite.end()
            return suite
        }
        
        func _run(group name: String, runs: [TestResult], suite: Suite) -> Group {
            let group = Group(name: name, suite: suite)
            
            let configAndFeature: (TestRetryGroupConfiguration, String)? = features.reduce(nil) { prev, feature in
                guard prev == nil else { return prev }
                return feature.testGroupConfiguration(for: group.name, meta: Group.self, in: suite).map {
                    ($0, feature.id)
                }
            }
            
            features.forEach { $0.testGroupWillStart(for: group.name, in: suite) }
            
            let skipStatus = configAndFeature.map(\.0).skipStatus
            var retryReason: String? = nil
            
            if let config = configAndFeature?.0, let featureId = configAndFeature?.1 {
                group.skipStrategy = config.skipStrategy
                group.successStrategy = config.successStrategy
                
                if config.skipStatus.isSkipped {
                    retryReason = _run(test: name, result: .skip(featureId), skipStatus: skipStatus,
                                       retryReason: retryReason, group: group)
                }
            }
            
            var runsIterator = runs.makeIterator()
            if !skipStatus.isSkipped, retryReason == nil {
                let run = runsIterator.next() ?? .fail(.init(type: "MOCK RUNNER: NO TEST RUN AVAILABLE"))
                retryReason = _run(test: name, result: run, skipStatus: skipStatus,
                                   retryReason: retryReason, group: group)
            }
            
            while retryReason != nil {
                let run = runsIterator.next() ?? .fail(.init(type: "MOCK RUNNER: NO TEST RUN AVAILABLE"))
                retryReason = _run(test: name, result: run, skipStatus: skipStatus,
                                   retryReason: retryReason, group: group)
            }
            
            return group
        }
        
        func _run(test name: String, result: TestResult, skipStatus: SkipStatus, retryReason: String?, group: Group) -> String? {
            let test = Test(name: name, suite: group.suite)
            
            for feature in features {
                feature.testWillStart(test: test, retryReason: retryReason,
                                      skipStatus: skipStatus,
                                      executionCount: group.executionCount,
                                      failedExecutionCount: group.failedExecutionCount)
            }
            
            var newTestResult = result
            
            if case .fail(let testError) = result.result {
                test.add(error: testError)
                
                let suppress = features.reduce((false, "")) { prev, feature in
                    guard !prev.0 else { return prev }
                    let suppress =  feature.shouldSuppressError(test: test, skipStatus: skipStatus,
                                                                executionCount: group.executionCount,
                                                                failedExecutionCount: group.failedExecutionCount)
                    return (suppress, feature.id)
                }
                
                if suppress.0 {
                    newTestResult = .pass()
//                    print("Suppressed issue \(test) for test \(testCase) reason \(suppress.1)")
                }
            }
            
            // We are using original status. Error could be suppressed by feature
            let status: TestStatus = result.status
            for feature in features {
                feature.testWillFinish(test: test, duration: result.duration, withStatus: status,
                                       skipStatus: skipStatus,
                                       executionCount: group.executionCount,
                                       failedExecutionCount: group.failedExecutionCount)
            }
            
            let actionAndFeature: (RetryStatus, String)? = features.reduce(nil) { prev, feature in
                guard prev == nil else { return prev }
                return feature.testGroupRetry(test: test, duration: result.duration, withStatus: status,
                                              skipStatus: skipStatus,
                                              executionCount: group.executionCount,
                                              failedExecutionCount: group.failedExecutionCount).map {
                    ($0, feature.id)
                }
            }
            
            var newRetryReason: String? = nil
            
            if let actionAndFeature = actionAndFeature {
                switch actionAndFeature {
                case (.retry, let id):
                    newRetryReason = id
                case (.recordErrors, _):
                    newTestResult = result
                case (.pass, _): break
                }
            }
            
            test.end(status: newTestResult.status)
            group.add(run: test)
            
            return newRetryReason
        }
    }
}
