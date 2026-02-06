/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogSDKTesting
import protocol EventsExporter.Logger
import OpenTelemetryApi

enum Mocks {
    class TestBase: TestContainer {
        var id: SpanId = .random()
        var name: String
        var startTime: Date = Date()
        var duration: UInt64 = 0
        var status: TestStatus = .pass
        var tags: [String: String] = [:]
        var metrics: [String: Double] = [:]
        
        init(name: String) {
            self.name = name
        }
        
        func set(failed reason: TestError?) {
            status = .fail
        }
        
        func set(skipped reason: String? = nil) {
            status = .skip
            if let reason = reason {
                tags[DDTestTags.testSkipReason] = reason
            }
        }
        
        func set(tag name: String, value: any SpanAttributeConvertible) {
            tags[name] = value.spanAttribute
        }
        
        func end(time: Date?) {
            duration = (time ?? Date()).timeIntervalSince(startTime).toNanosecondsUInt
        }
        
        func set(metric name: String, value: Double) {
            metrics[name] = value
        }
    }
    
    final class Session: TestBase, TestSession, Hashable, Equatable, CustomDebugStringConvertible {
        var testIndex: UInt = 0
        var testFramework: String = ""
        
        var modules: [String: Module] = [:]
        
        func nextTestIndex() -> UInt {
            defer { testIndex += 1 }
            return testIndex
        }
        
        func add(module: Module) {
            guard module.session.id == self.id else { return }
            modules[module.name] = module
        }
        
        subscript(_ module: String) -> Module? {
            modules[module]
        }
        
        var debugDescription: String {
            let mods = modules.values.map{ $0.debugDescription }
            return "[\(mods.joined(separator: ", "))]"
        }
        
        static func == (lhs: Mocks.Session, rhs: Mocks.Session) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(name)
        }
    }
    
    final class Module: TestBase, TestModule, Hashable, Equatable, CustomDebugStringConvertible {
        weak var _session: Session?
        var session: any TestSession { _session! }
        var localization: String = ""
        
        var suites: [String: Suite] = [:]
        
        init(name: String, session: Session) {
            self._session = session
            super.init(name: name)
        }
        
        func add(suite: Suite) {
            guard suite.module.id == self.id else { return }
            suites[suite.name] = suite
        }
        
        subscript(_ suite: String) -> Suite? {
            suites[suite]
        }
        
        var debugDescription: String {
            let suites = suites.values.map{ $0.debugDescription }
            return "\(name): [\(suites.joined(separator: ", "))]"
        }
        
        static func == (lhs: Mocks.Module, rhs: Mocks.Module) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name && lhs._session == rhs._session
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(name)
            hasher.combine(_session)
        }
    }
    
    final class Suite: TestBase, TestSuite, Hashable, Equatable, CustomDebugStringConvertible {
        weak var _module: Module?
        var module: any TestModule { _module! }
        var localization: String = ""
        
        var unskippable: Bool = false
        var tests: [String: Group] = [:]
        
        init(name: String, module: Module) {
            self._module = module
            super.init(name: name)
        }
        
        func add(group: Group) {
            guard group.suite == nil || group.suite?.id == self.id else { return }
            group.suite = self
            tests[group.name] = group
        }
        
        subscript(_ test: String) -> Group? {
            tests[test]
        }
        
        var debugDescription: String {
            let tests = tests.values.map{ $0.debugDescription }
            return "\(name): [\(tests.joined(separator: ", "))]"
        }
        
        static func == (lhs: Mocks.Suite, rhs: Mocks.Suite) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name && lhs._module == rhs._module
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(name)
            hasher.combine(_module)
        }
    }
    
    final class Group: UnskippableMethodCheckerFactory, Equatable, Hashable, CustomDebugStringConvertible {
        var name: String
        weak var suite: Suite!
        var unskippable: Bool = false
        var runs: [Test] = []
        
        var skipStrategy: RetryGroupSkipStrategy = .allSkipped
        var successStrategy: RetryGroupSuccessStrategy = .allSucceeded
        
        init(name: String, suite: Suite, unskippable: Bool) {
            self.name = name
            self.suite = suite
            self.unskippable = unskippable
        }
        
        func add(run: Test) {
            runs.append(run)
        }
        
        subscript(_ run: Int) -> Test? {
            guard run >= 0 && run < runs.count else { return nil }
            return runs[run]
        }
        
        var classId: ObjectIdentifier { ObjectIdentifier(self) }
        
        var unskippableMethods: UnskippableMethodChecker {
            .init(isSuiteUnskippable: suite.unskippable,
                  skippableMethods: [name: !unskippable])
        }
        
        var executionCount: Int { runs.filter { $0.duration > 0 }.count }
        var failedExecutionCount: Int { runs.filter { $0.status == .fail }.count }
        
        var isSucceeded: Bool {
            switch successStrategy {
            case .allSucceeded:
                return runs.allSatisfy { $0.status == .pass }
            case .atLeastOneSucceeded:
                return runs.contains { $0.status == .pass }
            case .atMostOneFailed:
                return failedExecutionCount <= 1
            case .alwaysSucceeded: return true
            }
        }
        
        var isSkipped: Bool {
            switch skipStrategy {
            case .allSkipped:
                return runs.allSatisfy { $0.status == .skip }
            case .atLeastOneSkipped:
                return runs.contains { $0.status == .skip }
            }
        }
        
        var debugDescription: String {
            let tests = runs.map{ $0.debugDescription }
            return "\(name): [\(tests.joined(separator: ", "))]"
        }
        
        static func == (lhs: Mocks.Group, rhs: Mocks.Group) -> Bool {
            lhs.name == rhs.name && lhs.suite === rhs.suite
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            hasher.combine(suite)
        }
    }
    
    enum ErrorSuppressionStatus: Equatable, Hashable {
        case normal
        case suppressed(by: FeatureId)
        case unsuppressed(by: FeatureId)
        
        var isSuppressed: Bool {
            switch self {
            case .suppressed(_): return true
            default: return false
            }
        }
    }
    
    final class Test: TestBase, TestRun, Hashable, Equatable, CustomDebugStringConvertible {
        weak var _suite: Suite?
        var suite: any TestSuite { _suite! }
        var error: TestError? = nil
        var errorStatus: ErrorSuppressionStatus = .normal
        
        var xcStatus: TestStatus {
            guard status == .fail else { return status }
            return errorStatus.isSuppressed ? .pass : .fail
        }
        
        init(name: String, suite: Suite) {
            self._suite = suite
            super.init(name: name)
        }
        
        func add(error: TestError) {
            self.error = error
            tags[DDTags.errorType] = error.type
            tags[DDTags.errorMessage] = error.message
            tags[DDTags.errorStack] = error.stack
        }
        
        func add(benchmark name: String, samples: [Double], info: String?) {
            tags[DDTestTags.testType] = DDTagValues.typeBenchmark
        }
        
        func end(status: TestStatus, time: Date?) {
            super.end(time: time)
            self.status = status
        }
        
        var debugDescription: String {
            return "\(name)>\(status)"
        }
        
        static func == (lhs: Mocks.Test, rhs: Mocks.Test) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name && lhs._suite == rhs._suite
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(name)
            hasher.combine(_suite)
        }
    }
    
    final class CatchLogger: EventsExporter.Logger {
        var logs: [String]
        var isDebug: Bool
        
        init(isDebug: Bool = true) {
            self.logs = []
            self.isDebug = isDebug
        }
        
        func clear() {
            self.logs.removeAll()
        }
        
        func print(_ message: String) {
            print(prefix: "[DatadogSDKTesting] ", message: message)
        }
        
        func debug(_ wrapped: @autoclosure () -> String) {
            if isDebug {
                print(prefix: "[Debug][DatadogSDKTesting] ", message: wrapped())
            }
        }
        
        func measure<T>(name: String, _ operation: () throws -> T) rethrows -> T {
            if isDebug {
                let startTime = CFAbsoluteTimeGetCurrent()
                defer {
                    let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
                    print(prefix: "[Debug][DatadogSDKTesting] ", message: "Time elapsed for \(name): \(timeElapsed) s.")
                }
                return try operation()
            } else {
                return try operation()
            }
        }
        
        private func print(prefix: String, message: String) {
            logs.append("\(prefix)\(message)")
        }
    }
    
    final class CoverageCollector: TestCoverageCollector {
        var testStarted: Bool = false
        var tests: Set<String> = []
        
        func startTest() {
            assert(!testStarted, "Test should not be started more than once")
            testStarted = true
        }
        
        func endTest(testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64) {
            assert(testStarted, "Test should not be stopped more than once")
            testStarted = false
            tests.insert(String(describing: (testSessionId, testSuiteId, spanId)))
        }
        
        func has(testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64) -> Bool {
            return tests.contains(String(describing: (testSessionId, testSuiteId, spanId)))
        }
        
        static var id: FeatureId { "CoverageCollector" }
        func stop() {}
    }
}
