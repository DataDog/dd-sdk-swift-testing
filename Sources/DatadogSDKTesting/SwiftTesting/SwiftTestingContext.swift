/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

protocol SwiftTestingTestInfoType: Sendable {
    var name: String { get }
    var module: String { get }
    var isSuite: Bool { get }
    var hasSuite: Bool { get }
    var suite: String { get }
    var isParameterized: Bool { get }
}

protocol SwiftTestingTestRunInfoType: SwiftTestingTestInfoType {
    // This is a private API for now in the swift testing
    // var parameters: [(name: String, value: String)] { get }
}

enum SwiftTestingTestStatus: Equatable, Hashable, Sendable {
    case skipped(reason: String)
    case failed
    case passed
    
    var testStatus: TestStatus {
        switch self {
        case .skipped(_): return .skip
        case .failed: return .fail
        case .passed: return .pass
        }
    }
}

public enum SwiftTestingRegistryError: Error {
    case unknownSuite(name: String, module: String)
    case moduleAlreadyEnded(name: String)
    case moduleNotFound(name: String)
}

enum SwiftTestingTestRunRetry: Equatable, Hashable, Sendable {
    case skipped(reason: String)
    case retry(RetryStatus)
}

protocol SwiftTestingTestRegistryType: AnyObject, Sendable {
    var registeredTests: [String: [String: Set<String>]] { get async }
    
    func register(test: some SwiftTestingTestInfoType) async throws
    func count(for suite: some SwiftTestingTestInfoType) async throws -> Int
    func tests(for suite: some SwiftTestingTestInfoType) async throws -> Set<String>
    func suites(for module: String) async throws -> Set<String>
}

protocol SwiftTestingSuiteProviderType: AnyObject, Sendable {
    var registry: any SwiftTestingTestRegistryType { get }
    
    func with(suite: some SwiftTestingTestInfoType,
              performing function: @Sendable (borrowing SwiftTestingSuiteContext) async throws -> Void) async throws
    
    func with(virtual test: some SwiftTestingTestInfoType,
              performing function: @Sendable (borrowing SwiftTestingSuiteContext) async throws -> Void) async throws
}

struct SwiftTestingTestRunContext: Sendable {
    let test: any TestRun
    let group: SwiftTestingRetryGroupContext
    let info: any SwiftTestingTestRunInfoType
    
    var observer: any SwiftTestingObserverType {
        group.test.suite.observer
    }
    
    var shouldSuppressError: Bool {
        group.observer.shouldSuppressError(for: self)
    }
}

struct SwiftTestingRetryGroupContext: Sendable {
    let test: SwiftTestingTestContext
    let configuration: RetryGroupConfiguration
    
    var observer: any SwiftTestingObserverType {
        test.suite.observer
    }
    
    func with(
        run: some SwiftTestingTestRunInfoType,
        performing function: @Sendable (borrowing SwiftTestingTestRunContext) async -> SwiftTestingTestStatus
    ) async -> SwiftTestingTestRunRetry {
        let test = test.createTestRun(named: run.name)
        let context = SwiftTestingTestRunContext(test: test, group: self, info: run)
        await observer.willStart(testRun: context)
        let status = await function(context)
        let config = await observer.willFinish(testRun: context, with: status)
        test.end(status: status.testStatus)
        await observer.didFinish(testRun: context)
        return config
    }
}

struct SwiftTestingTestContext: Sendable {
    let suite: SwiftTestingSuiteContext
    let info: any SwiftTestingTestInfoType
    
    var observer: any SwiftTestingObserverType {
        suite.observer
    }
    
    func createTestRun(named: String) -> any TestRun {
        suite.createTestRun(named: named)
    }
    
    func with(group forTest: some SwiftTestingTestRunInfoType,
              performing function: @Sendable (borrowing SwiftTestingRetryGroupContext) async throws -> Void) async throws {
        let config = await observer.runGroupConfiguration(test: self)
        let group = SwiftTestingRetryGroupContext(test: self, configuration: config)
        await observer.willStart(group: group)
        try await doThrow {
            try await function(group)
        } finally: {
            await observer.didFinish(group: group)
        }
    }
}

struct SwiftTestingSuiteContext: Sendable {
    actor State {
        private var _tests: Set<String>
        
        var isEnded: Bool { _tests.isEmpty }
        
        init(tests: Set<String>) {
            self._tests = tests
        }
        
        func end(test: some SwiftTestingTestInfoType) {
            _tests.remove(test.name)
        }
    }
    
    private let _state: State?
    private let _suite: any TestSuite & TestRunProvider
    
    var suite: any TestSuite { _suite }
    let info: any SwiftTestingTestInfoType
    let observer: any SwiftTestingObserverType
    let testsCount: Int
    
    init(suite: any TestSuite & TestRunProvider,
         info: any SwiftTestingTestInfoType, testsCount: Int,
         observer: any SwiftTestingObserverType)
    {
        self.init(suite: suite, testsCount: testsCount,
                  state: nil, info: info, observer: observer)
    }
   
    init(suite: any TestSuite & TestRunProvider, tests: Set<String>,
         info: any SwiftTestingTestInfoType,
         observer: any SwiftTestingObserverType)
    {
        self.init(suite: suite, testsCount: tests.count,
                  state: .init(tests: tests), info: info, observer: observer)
    }
    
    private init(suite: any TestSuite & TestRunProvider,
                 testsCount: Int, state: State?,
                 info: any SwiftTestingTestInfoType,
                 observer: any SwiftTestingObserverType)
    {
        self.testsCount = testsCount
        self._state = state
        self._suite = suite
        self.info = info
        self.observer = observer
    }
    
    func createTestRun(named: String) -> any TestRun {
        _suite.startTest(named: named)
    }
    
    func end() async -> Bool {
        guard let state = _state else { // Normal suite
            _suite.end()
            return true
        }
        // Virtual suite
        guard await state.isEnded else { // we have more tests
            return false
        }
        // no more tests. we can end
        _suite.end()
        return true
    }
    
    func with(test: some SwiftTestingTestInfoType,
              performing function: @Sendable (borrowing SwiftTestingTestContext) async throws -> Void) async throws
    {
        let context = SwiftTestingTestContext(suite: self, info: test)
        await observer.willStart(test: context)
        try await doThrow {
            try await function(context)
        } finally: {
            await observer.didFinish(test: context)
            await _state?.end(test: test)
        }
    }
}

final class SwiftTestingSuiteProvider: SwiftTestingSuiteProviderType {
    actor Registry: SwiftTestingTestRegistryType {
        private var _tests: [String: [String: Set<String>]] = [:]
        
        var registeredTests: [String: [String: Set<String>]] {
            _tests
        }
        
        func register(test: some SwiftTestingTestInfoType) {
            if !test.isSuite {
                _tests[test.module, default: [:]][test.suite, default: []].insert(test.name)
            }
        }
        
        func count(for suite: some SwiftTestingTestInfoType) throws -> Int {
            try tests(for: suite).count
        }
        
        func tests(for suite: some SwiftTestingTestInfoType) throws -> Set<String> {
            guard let module = _tests[suite.module] else {
                throw SwiftTestingRegistryError.moduleNotFound(name: suite.module)
            }
            guard let tests = module[suite.suite] else {
                throw SwiftTestingRegistryError.unknownSuite(name: suite.suite, module: suite.module)
            }
            return tests
        }
        
        func suites(for module: String) throws -> Set<String> {
            guard let keys = _tests[module]?.keys else {
                throw SwiftTestingRegistryError.moduleNotFound(name: module)
            }
            return Set(keys)
        }
    }
    
    actor State {
        final class ModuleContext {
            var module: any TestModule & TestSuiteProvider
            var active: [String: Task<SwiftTestingSuiteContext, any Error>]
            var left: Set<String>
            
            init(module: any TestModule & TestSuiteProvider, left: Set<String>) {
                self.module = module
                self.active = [:]
                self.left = left
            }
        }
        
        enum ModuleState {
            case notStarted
            case active(ModuleContext)
            case ended
        }
        
        private let _provider: any TestSessionProvider
        private var _session: Task<any TestSession & TestModuleProvider, any Error>? = nil
        private var _modules: [String: ModuleState] = [:]
        
        nonisolated let registry: Registry
        
        var activeSession: any TestSession & TestModuleProvider {
            get async throws {
                if let session = _session {
                    return try await session.value
                }
                _session = Task { try await self._provider.startSession() }
                return try await _session!.value
            }
        }
        
        init(provider: any TestSessionProvider, registry: Registry) {
            self._provider = provider
            self.registry = registry
        }
        
        func module(name: String) async throws -> ModuleContext {
            let state = _modules[name, default: .notStarted]
            switch state {
            case .active(let context): return context
            case .ended: throw SwiftTestingRegistryError.moduleAlreadyEnded(name: name)
            case .notStarted: break
            }
            let session = try await self.activeSession
            let suites = try await self.registry.suites(for: name)
            if case .active(let context) = _modules[name] {
                // other thread created it
                return context
            }
            let module = session.startModule(named: name)
            let context = ModuleContext(module: module, left: suites)
            _modules[name] = .active(context)
            return context
        }
        
        func suite(named suite: String, in module: String,
                   factory: @Sendable @escaping (any TestModule & TestSuiteProvider) async throws ->  SwiftTestingSuiteContext) async throws -> (suite: SwiftTestingSuiteContext, isNew: Bool)
        {
            let module = try await self.module(name: module)
            if let suite = module.active[suite] {
                return try await (suite.value, false)
            }
            let task = Task { try await factory(module.module) }
            module.active[suite] = task
            module.left.remove(suite)
            return try await (task.value, true)
        }
        
        func didEnded(suite: any TestSuite) throws -> Bool {
            guard case .active(let context) = _modules[suite.module.name] else {
                throw SwiftTestingRegistryError.moduleAlreadyEnded(name: suite.module.name)
            }
            context.active.removeValue(forKey: suite.name)
            if context.left.isEmpty && context.active.isEmpty {
                _modules[suite.module.name] = .ended
                return true
            }
            _modules[suite.module.name] = .active(context)
            return false
        }
    }
    
    var registry: any SwiftTestingTestRegistryType { _state.registry }
    let observer: any SwiftTestingObserverType
    private let _state: State
    
    init(provider: any TestSessionProvider, observer: any SwiftTestingObserverType) {
        self._state = .init(provider: provider, registry: Registry())
        self.observer = observer
    }
    
    func with(suite info: some SwiftTestingTestInfoType,
              performing function: @Sendable (borrowing SwiftTestingSuiteContext) async throws -> Void) async throws
    {
        let suite = try await self._state.suite(named: info.suite, in: info.module) { mod in
            let count = try await self.registry.count(for: info)
            let suite = mod.startSuite(named: info.suite)
            return .init(suite: suite, info: info, testsCount: count, observer: self.observer)
        }
        if suite.isNew {
            await observer.willStart(suite: suite.suite)
        }
        try await with(context: suite.suite, performing: function)
    }
    
    func with(virtual test: some SwiftTestingTestInfoType,
              performing function: @Sendable (borrowing SwiftTestingSuiteContext) async throws -> Void) async throws
    {
        let suite = try await self._state.suite(named: test.suite, in: test.module) { mod in
            let tests = try await self.registry.tests(for: test)
            let suite = mod.startSuite(named: test.suite)
            return SwiftTestingSuiteContext(suite: suite, tests: tests, info: test, observer: self.observer)
        }
        if suite.isNew {
            await observer.willStart(suite: suite.suite)
        }
        try await with(context: suite.suite, performing: function)
    }
    
    private func with(context: SwiftTestingSuiteContext,
                      performing function: @Sendable (borrowing SwiftTestingSuiteContext) async throws -> Void) async throws
    {
        try await doThrow {
            try await function(context)
        } finally: {
            if await context.end() {
                await observer.didFinish(suite: context)
                if try await _state.didEnded(suite: context.suite) {
                    context.suite.module.end()
                }
            }
        }
    }
    
    var session: any TestSession & TestModuleProvider {
        get async throws {
            try await _state.activeSession
        }
    }
}

func doThrow<R>(_ body: @Sendable () async throws -> R, finally: @Sendable () async throws -> Void) async throws -> R {
    var catched: Error? = nil
    let value: R?
    do {
        value = try await body()
    } catch {
        catched = error
        value = nil
    }
    try await finally()
    if let catched { throw catched }
    return value!
}
