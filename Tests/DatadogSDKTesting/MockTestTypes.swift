/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogSDKTesting
@preconcurrency import OpenTelemetryApi

protocol MockTestModuleInfo {
    var duration: UInt64 { get set }
    var status: TestStatus { get set }
    var tags: [String: String] { get set }
    var metrics: [String: Double] { get set }
    init()
}

enum Mocks {
    struct ModuleInfo: MockTestModuleInfo {
        var duration: UInt64 = 0
        var status: TestStatus = .pass
        var tags: [String: String] = [:]
        var metrics: [String: Double] = [:]
    }
    
    class TestBase<Info: MockTestModuleInfo>: TestContainer, @unchecked Sendable {
        let _state: Synced<Info> = .init(.init())
        
        let id: SpanId = .random()
        let name: String
        let startTime: Date
        var duration: UInt64 {
            get { _state.value.duration }
            set { _state.update { $0.duration = newValue } }
        }
        var status: TestStatus { _state.value.status }
        var tags: [String: String] { _state.value.tags }
        var metrics: [String: Double] { _state.value.metrics }
        
        init(name: String, startTime: Date = Date()) {
            self.name = name
            self.startTime = startTime
        }
        
        func set(failed reason: TestError?) {
            _state.update { $0.status = .fail }
        }
        
        func set(skipped reason: String? = nil) {
            _state.update {
                $0.status = .skip
                if let reason = reason {
                    $0.tags[DDTestTags.testSkipReason] = reason
                }
            }
        }
        
        func set(tag name: String, value: any SpanAttributeConvertible) {
            _state.update {
                $0.tags[name] = value.spanAttribute
            }
        }
        
        func end(time: Date?) {
            _state.update {
                if $0.duration == 0 {
                    $0.duration = (time ?? Date()).timeIntervalSince(startTime).toNanoseconds
                }
            }
        }
        
        func set(metric name: String, value: Double) {
            _state.update {
                $0.metrics[name] = value
            }
        }
    }
    
    final class Session: TestBase<Session.SessionInfo>, TestSession, TestModuleProvider, TestModuleManager, Hashable, Equatable, CustomDebugStringConvertible, @unchecked Sendable {
        struct SessionInfo: MockTestModuleInfo {
            var duration: UInt64 = 0
            var status: TestStatus = .pass
            var tags: [String: String] = [:]
            var metrics: [String: Double] = [:]
            var testIndex: UInt = 0
            var testFrameworks: Set<String> = []
            var modules: [String: Module] = [:]
        }

        let _sessionConfig: SessionConfig?
        let _moduleObserver: (any TestModuleManagerObserver)?
        
        let unskippable: [String: [String: (Bool, [String: Bool])]]

        init(name: String, startTime: Date = Date(),
             unskippable: [String: [String: (Bool, [String: Bool])]],
             config: SessionConfig? = nil,
             observer: (any TestModuleManagerObserver)? = nil) {
            self._sessionConfig = config
            self._moduleObserver = observer
            self.unskippable = unskippable
            super.init(name: name, startTime: startTime)
        }

        var modules: [String: Module] { _state.value.modules }
        var testFrameworks: Set<String> { _state.value.testFrameworks }

        func nextTestIndex() -> UInt {
            _state.update { state in
                defer { state.testIndex += 1 }
                return state.testIndex
            }
        }

        subscript(_ module: String) -> Module? {
            _state.value.modules[module]
        }

        var debugDescription: String {
            let mods = _state.value.modules.values.map{ $0.debugDescription }
            return "[\(mods.joined(separator: ", "))]"
        }

        static func == (lhs: Mocks.Session, rhs: Mocks.Session) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(name)
        }
        
        func newModule(named name: String, at start: Date?) -> Mocks.Module {
            Mocks.Module(name: name, session: self,
                         unskippable: unskippable[name] ?? [:],
                         startTime: start ?? Date())
        }

        func startModule(named name: String, at start: Date?) -> any TestModule & TestSuiteProvider {
            newModule(named: name, at: start)
        }

        func module(named name: String) -> any DatadogSDKTesting.TestModule & DatadogSDKTesting.TestSuiteProvider {
            let (module, started) = _state.update { state in
                if let module = state.modules[name] {
                    return (module, false)
                }
                let module = newModule(named: name, at: nil)
                state.modules[name] = module
                return (module, true)
            }
            if let config = _sessionConfig, started {
                _moduleObserver?.didStart(module: module, with: config)
            }
            return module
        }

        func end(module: any TestModule) {
            if let config = _sessionConfig {
                _moduleObserver?.willFinish(module: module, with: config)
                module.end()
                _moduleObserver?.didFinish(module: module, with: config)
            } else {
                module.end()
            }
        }

        final class Provider: TestSessionProvider {
            nonisolated(unsafe) var session: Session? = nil
            
            let unskippable: [String: [String: (Bool, [String: Bool])]]
            
            init(unskippable: [String : [String : (Bool, [String : Bool])]] = [:]) {
                self.unskippable = unskippable
            }
            
            func startSession(named name: String, config: SessionConfig, startTime: Date,
                              observer: (any TestModuleManagerObserver)?) async throws -> any TestModuleManager & TestSession {
                self.session = Session(name: name, startTime: startTime, unskippable: unskippable,
                                       config: config, observer: observer)
                return self.session!
            }
        }
    }
    
    final class Module: TestBase<Module.ModuleInfo>, TestModule, TestSuiteProvider, Hashable, Equatable, CustomDebugStringConvertible, @unchecked Sendable {
        struct ModuleInfo: MockTestModuleInfo {
            var duration: UInt64 = 0
            var status: TestStatus = .pass
            var tags: [String: String] = [:]
            var metrics: [String: Double] = [:]
            var testFrameworks: Set<String> = []
            var suites: [String: Suite] = [:]
            var localization: String = ""
        }
        
#if compiler(>=6.3)
        weak let _session: Session!
#else
        weak var _session: Session!
#endif
        
        let unskippable: [String: (Bool, [String: Bool])]
        var session: any TestSession { _session }
        var testFrameworks: Set<String> { _state.value.testFrameworks }
        var suites: [String: Suite] { _state.value.suites }
        var localization: String {
            get { _state.value.localization }
            set { _state.update { $0.localization = newValue } }
        }
        
        init(name: String, session: Session, unskippable: [String: (Bool, [String: Bool])], startTime: Date = Date()) {
            self._session = session
            self.unskippable = unskippable
            super.init(name: name, startTime: startTime)
        }
        
        subscript(_ suite: String) -> Suite? {
            _state.value.suites[suite]
        }
        
        var debugDescription: String {
            let suites = _state.value.suites.values.map{ $0.debugDescription }
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
        
        func startSuite(named name: String, at start: Date?, framework: String) -> any DatadogSDKTesting.TestRunProvider & DatadogSDKTesting.TestSuite {
            let suite = _state.update { state in
                let suite = Mocks.Suite(name: name, module: self,
                                        framework: framework,
                                        unskippable: unskippable[name]?.0 ?? false,
                                        unskippableTests: unskippable[name]?.1 ?? [:],
                                        startTime: start ?? Date())
                state.suites[name] = suite
                state.testFrameworks.insert(framework)
                return suite
            }
            let _ = _session?._state.update {
                $0.testFrameworks.insert(framework)
            }
            return suite
        }
    }
    
    final class Suite: TestBase<Suite.SuiteInfo>, TestSuite, TestRunProvider, Hashable, Equatable, CustomDebugStringConvertible, @unchecked Sendable {
        struct SuiteInfo: MockTestModuleInfo {
            var duration: UInt64 = 0
            var status: TestStatus = .pass
            var tags: [String: String] = [:]
            var metrics: [String: Double] = [:]
            var tests: [String: Group] = [:]
            var localization: String = ""
            var unskippable: Bool = false
        }

#if compiler(>=6.3)
        weak let _module: Module!
#else
        weak var _module: Module!
#endif
        
        let testFramework: String
        let unskippableTests: [String: Bool]
        
        var module: any TestModule { _module }
        var localization: String {
            get { _state.value.localization }
            set { _state.update { $0.localization = newValue } }
        }
        var unskippable: Bool {
            get { _state.value.unskippable }
            set { _state.update { $0.unskippable = newValue } }
        }
        var tests: [String: Group] { _state.value.tests }
        
        init(name: String, module: Module, framework: String, unskippable: Bool, unskippableTests: [String: Bool], startTime: Date = Date()) {
            self._module = module
            self.testFramework = framework
            self.unskippableTests = unskippableTests
            super.init(name: name, startTime: startTime)
            self.unskippable = unskippable
        }
        
        subscript(_ test: String) -> Mocks.Group? {
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
        
        func startGroup(named name: String) -> Mocks.Group {
            _state.update { state in
                let group = Group(name: name, suite: self,
                                  unskippable: unskippableTests[name] ?? false)
                state.tests[name] = group
                return group
            }
        }
        
        func withTest<T>(named name: String, _ action: @Sendable (Test) async throws -> T) async rethrows -> T {
            let group = _state.update {
                if let group = $0.tests[name] {
                    return group
                }
                let group = Group(name: name, suite: self,
                                  unskippable: unskippableTests[name] ?? false)
                $0.tests[name] = group
                return group
            }
            return try await group.withTest(named: name, action)
        }

        func withTest<T>(named name: String, _ action: (Test) throws -> T) rethrows -> T {
            let group = _state.update {
                if let group = $0.tests[name] {
                    return group
                }
                let group = Group(name: name, suite: self, unskippable:
                                    unskippableTests[name] ?? false)
                $0.tests[name] = group
                return group
            }
            return try group.withTest(named: name, action)
        }
        
        func withActiveTest<T>(named name: String, _ action: @Sendable (any TestRun) async throws -> T) async rethrows -> T {
            try await withTest(named: name, action)
        }

        func withActiveTest<T>(named name: String, _ action: (any TestRun) throws -> T) rethrows -> T {
            try withTest(named: name, action)
        }
    }
    
    final class Group: UnskippableMethodCheckerFactory, Equatable, Hashable, CustomDebugStringConvertible, Sendable {
        struct GroupInfo {
            var unskippable: Bool = false
            var runs: [Test] = []
            
            var skipStrategy: RetryGroupSkipStrategy = .allSkipped
            var successStrategy: RetryGroupSuccessStrategy = .allSucceeded
        }
        
        let name: String

#if compiler(>=6.3)
        weak let suite: Suite!
#else
        weak var suite: Suite!
#endif

        let _state: Synced<GroupInfo> = .init(.init())
        
        var unskippable: Bool {
            get { _state.value.unskippable }
            set { _state.update { $0.unskippable = newValue } }
        }
        var skipStrategy: RetryGroupSkipStrategy {
            get { _state.value.skipStrategy }
            set { _state.update { $0.skipStrategy = newValue } }
        }
        
        var successStrategy: RetryGroupSuccessStrategy {
            get { _state.value.successStrategy }
            set { _state.update { $0.successStrategy = newValue } }
        }
        
        var runs: [Test] { _state.value.runs }
        
        init(name: String, suite: Suite, unskippable: Bool) {
            self.name = name
            self.suite = suite
            self.unskippable = unskippable
        }
        
        func withTest<T>(named name: String, _ action: (Mocks.Test) throws -> T) rethrows -> T {
            try Test.withActiveTest(name: name, group: self) { run in
                self._state.update { $0.runs.append(run) }
                return try action(run)
            }
        }
        
        func withTest<T>(named name: String, _ action: @Sendable (Test) async throws -> T) async rethrows -> T {
            try await Test.withActiveTest(name: name, group: self) { run in
                self._state.update { $0.runs.append(run) }
                return try await action(run)
            }
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
    
    final class Test: TestBase<Test.ModuleInfo>, TestRun, Hashable, Equatable, CustomDebugStringConvertible, @unchecked Sendable {
        struct ModuleInfo: MockTestModuleInfo {
            var duration: UInt64 = 0
            var status: TestStatus = .pass
            var tags: [String: String] = [:]
            var metrics: [String: Double] = [:]
            var error: TestError? = nil
            var errorStatus: ErrorSuppressionStatus = .normal
        }

#if compiler(>=6.3)
        weak let _group: Group?
#else
        weak var _group: Group?
#endif
        
        var suite: any TestSuite { _group!.suite }
        
        var error: TestError? { _state.value.error }
        var errorStatus: ErrorSuppressionStatus {
            get { _state.value.errorStatus }
            set { _state.update { $0.errorStatus = newValue } }
        }
        
        var xcStatus: TestStatus {
            guard status == .fail else { return status }
            return errorStatus.isSuppressed ? .pass : .fail
        }
        
        init(name: String, group: Group) {
            self._group = group
            super.init(name: name)
        }
        
        func set(status: TestStatus) {
            switch status {
            case .fail: set(failed: nil)
            case .skip: set(skipped: nil)
            case .pass: _state.update { $0.status = .pass }
            }
        }

        func add(error: TestError) {
            _state.update { state in
                state.error = error
                state.tags[DDTags.errorType] = error.type
                state.tags[DDTags.errorMessage] = error.message
                state.tags[DDTags.errorStack] = error.stack
            }
        }
        
        func add(benchmark name: String, samples: [Double], info: String?) {
            _state.update {
                $0.tags[DDTestTags.testType] = DDTagValues.typeBenchmark
            }
        }
        
        var debugDescription: String {
            return "\(name)>\(status)"
        }
        
        static func == (lhs: Mocks.Test, rhs: Mocks.Test) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name && lhs._group == rhs._group
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(name)
            hasher.combine(_group)
        }
        
        static func withActiveTest<T>(name: String, group: Group, _ body: (Self) throws -> T) rethrows -> T {
            let test = Self(name: name, group: group)
            defer { test.end() }
            return try test.withActive { try body(test) }
        }
        
        static func withActiveTest<T>(name: String, group: Group, _ body: @Sendable (Self) async throws -> T) async rethrows -> T {
            let test = Self(name: name, group: group)
            defer { test.end() }
            return try await test.withActive { try await body(test) }
        }
    }
    
    final class CatchLogger: DatadogSDKTesting.Logger {
        let logs: Synced<[String]>
        let isDebug: Bool
        
        init(isDebug: Bool = true) {
            self.logs = .init([])
            self.isDebug = isDebug
        }
        
        func clear() {
            self.logs.update { $0.removeAll() }
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
            logs.update { $0.append("\(prefix)\(message)") }
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
    
    final actor SessionManager: TestSessionManager {
        typealias SessionWithConfig = (session: any TestModuleManager & TestSession,
                                       config: SessionConfig)

        private var _session: Task<SessionWithConfig, any Error>?
        let provider: any TestSessionProvider
        let _config: SessionConfig
        let _observer: (any TestSessionManagerObserver & TestModuleManagerObserver)?

        init(provider: any TestSessionProvider, config: SessionConfig,
             observer: (any TestSessionManagerObserver & TestModuleManagerObserver)? = nil) {
            self._session = nil
            self.provider = provider
            self._config = config
            self._observer = observer
        }

        var sessionAndConfig: SessionWithConfig {
            get async throws {
                if let session = _session {
                    return try await session.value
                }
                let config = _config
                let provider = self.provider
                let observer = _observer
                _session = Task.detached {
                    let startTime = config.clock.now
                    let session = try await provider.startSession(named: "Mock.session", config: config,
                                                                  startTime: startTime, observer: observer)
                    await observer?.didStart(session: session, with: config)
                    return (session, config) as SessionWithConfig
                }
                return try await _session!.value
            }
        }

        func stop() async {
            guard let sc = try? await _session?.value else {
                return
            }
            await _observer?.willFinish(session: sc.session, with: sc.config)
            _session = nil
            sc.session.end()
            await _observer?.didFinish(session: sc.session, with: sc.config)
        }
    }
}
