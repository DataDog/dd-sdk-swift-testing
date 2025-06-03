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
        
        func setSkipped() { status = .skip }
        
        func set(tag name: String, value: any SpanAttributeConvertible) {
            tags[name] = value.spanAttribute
        }
        
        func end(time: Date?) {
            duration = (time ?? Date()).timeIntervalSince(startTime).toNanoseconds
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
        weak var _session: (any TestSession)?
        var session: any TestSession { _session! }
        var localization: String = ""
        
        var suites: [String: Suite] = [:]
        
        init(name: String, session: any TestSession) {
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
            lhs.id == rhs.id && lhs.name == rhs.name
                && lhs.session.id == rhs.session.id
                && lhs.session.name == rhs.session.name
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(name)
            hasher.combine(session.id)
            hasher.combine(session.name)
        }
    }
    
    final class Suite: TestBase, TestSuite, Hashable, Equatable, CustomDebugStringConvertible {
        weak var _module: (any TestModule)?
        var module: any TestModule { _module! }
        var localization: String = ""
        
        var tests: [String: Group] = [:]
        
        init(name: String, module: any TestModule) {
            self._module = module
            super.init(name: name)
        }
        
        func add(group: Group) {
            guard group.suite?.id == self.id else { return }
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
            lhs.id == rhs.id && lhs.name == rhs.name
                && lhs.session.id == rhs.session.id
                && lhs.session.name == rhs.session.name
                && lhs.module.id == rhs.module.id
                && lhs.module.name == rhs.module.name
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(name)
            hasher.combine(session.id)
            hasher.combine(session.name)
            hasher.combine(module.id)
            hasher.combine(module.name)
        }
    }
    
    final class Group: UnskippableMethodOwner, CustomDebugStringConvertible {
        static var classId: ObjectIdentifier { ObjectIdentifier(self) }
        static var unskippableMethods: UnskippableMethodChecker { .init(isSuiteUnskippable: false, skippableMethods: [:]) }
        
        var name: String
        weak var suite: (any TestSuite)!
        var runs: [Test] = []
        
        var skipStrategy: RetryGroupSkipStrategy = .allSkipped
        var successStrategy: RetryGroupSuccessStrategy = .allSucceeded
        
        init(name: String, suite: any TestSuite) {
            self.name = name
            self.suite = suite
        }
        
        func add(run: Test) {
            runs.append(run)
        }
        
        subscript(_ run: Int) -> Test? {
            guard run >= 0 && run < runs.count else { return nil }
            return runs[run]
        }
        
        var executionCount: Int { runs.count }
        var failedExecutionCount: Int { runs.filter { $0.status == .fail }.count }
        
        var isSucceeded: Bool {
            switch successStrategy {
            case .allSucceeded:
                return runs.allSatisfy { $0.status == .pass }
            case .atLeastOneSucceeded:
                return runs.contains { $0.status == .pass }
            case .atMostOneFailed:
                return failedExecutionCount <= 1
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
    }
    
    enum ErrorSuppressionStatus {
        case normal
        case suppressed
        case unsuppressed
    }
    
    final class Test: TestBase, TestRun, Hashable, Equatable, CustomDebugStringConvertible {
        weak var _suite: (any TestSuite)?
        var suite: any TestSuite { _suite! }
        var error: TestError? = nil
        var errorStatus: ErrorSuppressionStatus = .normal
        
        var xcStatus: TestStatus {
            guard status == .fail else { return status }
            return errorStatus == .suppressed ? .pass : .fail
        }
        
        init(name: String, suite: any TestSuite) {
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
            lhs.id == rhs.id && lhs.name == rhs.name
                && lhs.session.id == rhs.session.id
                && lhs.session.name == rhs.session.name
                && lhs.module.id == rhs.module.id
                && lhs.module.name == rhs.module.name
                && lhs.suite.id == rhs.suite.id
                && lhs.suite.name == rhs.suite.name
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(name)
            hasher.combine(session.id)
            hasher.combine(session.name)
            hasher.combine(module.id)
            hasher.combine(module.name)
            hasher.combine(suite.id)
            hasher.combine(suite.name)
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
}
