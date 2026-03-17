//
//  SwiftTestingObserver.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 13/03/2026.
//
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

enum SwiftTestingTestRunRetry: Equatable, Hashable, Sendable {
    case skipped(reason: String)
    case retry(RetryStatus)
}

protocol SwiftTestingTestRunContextType: Sendable {
    var test: any TestRun { get }
    var group: any SwiftTestingRetryGroupContextType { get }
    var info: any SwiftTestingTestRunInfoType { get }
    var shouldSuppressError: Bool { get }
}

extension SwiftTestingTestRunContextType {
    var observer: any SwiftTestingObserverType {
        group.test.suite.observer
    }
}

protocol SwiftTestingRetryGroupContextType: Sendable {
    var test: any SwiftTestingTestContextType { get }
    var configuration: RetryGroupConfiguration { get }
    
    func with(
        run: some SwiftTestingTestRunInfoType,
        performing function: @Sendable (any SwiftTestingTestRunContextType) async -> SwiftTestingTestStatus
    ) async -> SwiftTestingTestRunRetry
}

extension SwiftTestingRetryGroupContextType {
    var observer: any SwiftTestingObserverType {
        test.suite.observer
    }
}

protocol SwiftTestingTestContextType: Sendable {
    var suite: any SwiftTestingSuiteContextType { get }
    var info: any SwiftTestingTestInfoType { get }
    
    func with(group forTest: some SwiftTestingTestRunInfoType,
              performing function: @Sendable (any SwiftTestingRetryGroupContextType) async throws -> Void) async throws
}

extension SwiftTestingTestContextType {
    var observer: any SwiftTestingObserverType {
        suite.observer
    }
}

protocol SwiftTestingSuiteContextType: Sendable {
    var suite: any TestSuite { get }
    var info: any SwiftTestingTestInfoType { get }
    var observer: any SwiftTestingObserverType { get }
    
    func createTest(named: String) -> any TestRun
    
    func with(test: some SwiftTestingTestInfoType,
              performing function: @Sendable (any SwiftTestingTestContextType) async throws -> Void) async throws
}

protocol SwiftTestingSuiteRegistryType: AnyObject, Sendable {
    func register(test: some SwiftTestingTestInfoType) async throws
    
    func suite(
        virtual test: some SwiftTestingTestInfoType,
        or factory: @Sendable (Set<String>) async throws -> any SwiftTestingSuiteContextType
    ) async throws -> any SwiftTestingSuiteContextType
    
    func remove(suite: any SwiftTestingSuiteContextType) async
}

protocol SwiftTestingSuiteProviderType: AnyObject, Sendable {
    var registry: any SwiftTestingSuiteRegistryType { get }
    
    func with(suite: some SwiftTestingTestInfoType,
              performing function: @Sendable (any SwiftTestingSuiteContextType) async throws -> Void) async throws
    
    func with(virtual test: some SwiftTestingTestInfoType,
              performing function: @Sendable (any SwiftTestingSuiteContextType) async throws -> Void) async throws
}

struct SwiftTestingTestRunContext: SwiftTestingTestRunContextType {
    let test: any TestRun
    let group: any SwiftTestingRetryGroupContextType
    let info: any SwiftTestingTestRunInfoType
    
    var shouldSuppressError: Bool {
        group.observer.shouldSuppressError(for: self)
    }
}

struct SwiftTestingRetryGroupContext: SwiftTestingRetryGroupContextType {
    let test: any SwiftTestingTestContextType
    let configuration: RetryGroupConfiguration
    
    func with(
        run: some SwiftTestingTestRunInfoType,
        performing function: @Sendable (any SwiftTestingTestRunContextType) async -> SwiftTestingTestStatus
    ) async -> SwiftTestingTestRunRetry {
        let test = test.suite.createTest(named: run.name)
        let context = SwiftTestingTestRunContext(test: test, group: self, info: run)
        await observer.willStart(testRun: context)
        let status = await function(context)
        let config = await observer.willFinish(testRun: context, with: status)
        test.end(status: status.testStatus)
        await observer.didFinish(testRun: context)
        return config
    }
}

struct SwiftTestingTestContext: SwiftTestingTestContextType {
    let suite: any SwiftTestingSuiteContextType
    let info: any SwiftTestingTestInfoType
    
    func with(group forTest: some SwiftTestingTestRunInfoType,
              performing function: @Sendable (any SwiftTestingRetryGroupContextType) async throws -> Void) async throws {
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

struct SwiftTestingSuiteContext: SwiftTestingSuiteContextType {
    private let _suite: any TestSuite & TestRunProvider
    var suite: any TestSuite { _suite }
    let info: any SwiftTestingTestInfoType
    let observer: any SwiftTestingObserverType
    
    init(suite: any TestSuite & TestRunProvider, info: any SwiftTestingTestInfoType, observer: any SwiftTestingObserverType) {
        self._suite = suite
        self.info = info
        self.observer = observer
    }
    
    func createTest(named: String) -> any TestRun {
        _suite.startTest(named: named)
    }
    
    func with(test: some SwiftTestingTestInfoType,
              performing function: @Sendable (any SwiftTestingTestContextType) async throws -> Void) async throws {
        let context = SwiftTestingTestContext(suite: self, info: test)
        await observer.willStart(test: context)
        try await doThrow {
            try await function(context)
        } finally: {
            await observer.didFinish(test: context)
        }
    }
}

struct SwiftTestingVirtualSuiteContext: SwiftTestingSuiteContextType {
    actor State {
        private var _tests: Set<String>
        
        init(tests: Set<String>) {
            self._tests = tests
        }
        
        func end(test: some SwiftTestingTestInfoType) -> Bool {
            _tests.remove(test.name)
            return _tests.count == 0
        }
    }
    
    private let _state: State
    private let _registry: any SwiftTestingSuiteRegistryType
    private let _suite: any TestSuite & TestRunProvider
    
    var suite: any TestSuite { _suite }
    let info: any SwiftTestingTestInfoType
    let observer: any SwiftTestingObserverType
   
    init(suite: any TestSuite & TestRunProvider, tests: Set<String>, info: any SwiftTestingTestInfoType,
         observer: any SwiftTestingObserverType, registry: any SwiftTestingSuiteRegistryType)
    {
        self._state = .init(tests: tests)
        self._registry = registry
        self._suite = suite
        self.info = info
        self.observer = observer
    }
    
    func createTest(named: String) -> any TestRun {
        _suite.startTest(named: named)
    }
    
    func with(test: some SwiftTestingTestInfoType,
              performing function: @Sendable (any SwiftTestingTestContextType) async throws -> Void) async throws
    {
        let context = SwiftTestingTestContext(suite: self, info: test)
        await observer.willStart(test: context)
        try await doThrow {
            try await function(context)
        } finally: {
            await observer.didFinish(test: context)
            if await _state.end(test: test) {
                _suite.end()
                await observer.didFinish(suite: self)
            }
        }
    }
}

final class SwiftTestingSuiteProvider: SwiftTestingSuiteProviderType {
    actor Registry: SwiftTestingSuiteRegistryType {
        private var _tests: [String: [String: Set<String>]] = [:]
        private var _suites: [String: [String: any SwiftTestingSuiteContextType]] = [:]
        
        func register(test: some SwiftTestingTestInfoType) {
            if !test.isSuite && !test.hasSuite {
                _tests[test.module, default: [:]][test.suite, default: []].insert(test.name)
            }
        }
        
        func suite(
            virtual test: some SwiftTestingTestInfoType,
            or factory: @Sendable (Set<String>) async throws -> any SwiftTestingSuiteContextType
        ) async throws -> any SwiftTestingSuiteContextType {
            if let suite = _suites[test.module]?[test.suite] {
                return suite
            }
            let suite = try await factory(.init(_tests[test.module]?[test.suite] ?? []))
            _suites[test.module]?[test.suite] = suite
            return suite
        }
        
        func remove(suite: any SwiftTestingSuiteContextType) async {
            _suites[suite.suite.module.name]?[suite.suite.name] = nil
        }
    }
    
    actor State {
        private let _provider: any TestSessionProvider
        private var _module: Task<any TestModule & TestSuiteProvider, any Error>? = nil
        
        init(provider: any TestSessionProvider) {
            self._provider = provider
        }
        
        func module(or name: @autoclosure () -> String) async throws -> any TestModule & TestSuiteProvider {
            if let module = _module {
                return try await module.value
            }
            let named = name()
            _module = Task { try await self._provider.startSession().startModule(named: named) }
            return try await _module!.value
        }
    }
    
    let registry: any SwiftTestingSuiteRegistryType
    private let _state: State
    private let _observer: any SwiftTestingObserverType
    
    init(provider: any TestSessionProvider, observer: any SwiftTestingObserverType) {
        self.registry = Registry()
        self._state = .init(provider: provider)
        self._observer = observer
    }
    
    func with(suite info: some SwiftTestingTestInfoType,
              performing function: @Sendable (any SwiftTestingSuiteContextType) async throws -> Void) async throws
    {
        let suite = try await self.createSuite(test: info)
        let context = SwiftTestingSuiteContext(suite: suite, info: info, observer: _observer)
        await _observer.willStart(suite: context)
        
        try await doThrow {
            try await function(context)
        } finally: {
            suite.end()
            await _observer.didFinish(suite: context)
        }
    }
    
    func with(virtual test: some SwiftTestingTestInfoType,
              performing function: @Sendable (any SwiftTestingSuiteContextType) async throws -> Void) async throws
    {
        let suite = try await registry.suite(virtual: test) { tests in
            let suite = try await self.createSuite(test: test)
            let context = SwiftTestingVirtualSuiteContext(suite: suite, tests: tests, info: test,
                                                          observer: _observer, registry: self.registry)
            await _observer.willStart(suite: context)
            return context
        }
        try await function(suite)
        // We don't end suite. It will end automatically when all tests will be finished
    }
    
    private func createSuite(test: some SwiftTestingTestInfoType) async throws -> any TestSuite & TestRunProvider {
        try await self._state.module(or: test.module).startSuite(named: test.suite)
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
