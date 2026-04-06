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

struct SwiftTestingSourceLocation {
    let fileID: String
    let filePath: String
    let line: Int
    let column: Int
}

protocol SwiftTestingTestRunInfoType: SwiftTestingTestInfoType {
    var parameters: TestRunParameters { get }
    var location: SwiftTestingSourceLocation { get }
}

protocol SwiftTestingIssue: Sendable {
    var comment: String? { get }
    var isWarning: Bool { get }
    var error: (any Error)? { get }
    var location: SwiftTestingSourceLocation? { get }
    func record(test location: SwiftTestingSourceLocation)
}

enum SwiftTestingTestStatus: Sendable {
    enum Issues {
        case suppressed([SwiftTestingIssue])
        case unsuppressed([SwiftTestingIssue])
    }
    
    enum Errors {
        case catched(error: any Error, suppressed: Bool, issues: [SwiftTestingIssue])
        case issues(Issues)
        
        mutating func add(issue: SwiftTestingIssue) -> Bool {
            switch self {
            case .catched(error: let err, suppressed: let sup, issues: var issues):
                issues.append(issue)
                self = .catched(error: err, suppressed: sup, issues: issues)
                return sup
            case .issues(let issues):
                switch issues {
                case .suppressed(var sup):
                    sup.append(issue)
                    self = .issues(.suppressed(sup))
                    return true
                case .unsuppressed(var unsup):
                    unsup.append(issue)
                    self = .issues(.unsuppressed(unsup))
                    return false
                }
            }
        }
        
        mutating func catched(error: any Error) {
            guard case .issues(let issues) = self else {
                // can't happen. We can't have double throw
                return
            }
            switch issues {
            case .suppressed(let issues):
                self = .catched(error: error, suppressed: true, issues: issues)
            case .unsuppressed(let issues):
                self = .catched(error: error, suppressed: false, issues: issues)
            }
        }
    }
    
    case skipped(feature: FeatureId, reason: String, issues: Issues?)
    case failed(Errors)
    case passed
    
    var testStatus: TestStatus {
        switch self {
        case .skipped: return .skip
        case .failed: return .fail
        case .passed: return .pass
        }
    }
    
    var isFailed: Bool {
        switch self {
        case .failed: return true
        default: return false
        }
    }
    
    var isSkipped: Bool {
        switch self {
        case .skipped: return true
        default: return false
        }
    }
    
    var errors: Errors? {
        switch self {
        case .failed(let errors): return errors
        case .skipped(feature: _, reason: _, issues: let issues): return issues.map { .issues($0) }
        default: return nil
        }
    }
    
    var errorsWereRecorded: Bool {
        switch self {
        case .failed(.catched(error: _, suppressed: false, issues: _)): return true
        case .failed(.issues(.unsuppressed(_))): return true
        case .skipped(feature: _, reason: _, issues: .unsuppressed(_)): return true
        default: return false
        }
    }
    
    var asUnsuppressed: Self {
        switch self {
        case .failed(.catched(error: let err, suppressed: true, issues: let isues)):
            return .failed(.catched(error: err, suppressed: false, issues: isues))
        case .failed(.issues(.suppressed(let issues))):
            return .failed(.issues(.unsuppressed(issues)))
        case .skipped(feature: let feat, reason: let reas, issues: .suppressed(let issues)):
            return .skipped(feature: feat, reason: reas, issues: .unsuppressed(issues))
        default: return self
        }
    }
}

public enum SwiftTestingRegistryError: Error {
    case unknownSuite(name: String, module: String)
    case moduleAlreadyEnded(name: String)
    case moduleNotFound(name: String)
}

protocol SwiftTestingTestRegistryType: AnyObject, Sendable {
    var registeredTests: [String: [String: Set<String>]] { get async }
    
    func register(test: some SwiftTestingTestInfoType) async throws
    func count(for suite: some SwiftTestingTestInfoType) async throws -> Int
    func tests(for suite: some SwiftTestingTestInfoType) async throws -> Set<String>
    func suites(for module: String) async throws -> Set<String>
}

protocol SwiftTestingSuiteProviderType: Sendable {
    var registry: any SwiftTestingTestRegistryType { get }
    
    func with(suite: some SwiftTestingTestInfoType,
              performing function: @Sendable (borrowing SwiftTestingSuiteContext) async throws -> Void) async throws
    
    func with(virtual test: some SwiftTestingTestInfoType,
              performing function: @Sendable (borrowing SwiftTestingSuiteContext) async throws -> Void) async throws
}

struct SwiftTestingTestRunContext: Sendable {
    let testRun: any TestRun
    let test: SwiftTestingTestContext
    let info: any SwiftTestingTestRunInfoType
    
    var configuration: SessionConfig {
        test.configuration
    }
    
    var observer: any SwiftTestingObserverType {
        test.observer
    }
    
    func shouldSuppressError(info: TestRunInfoStart) -> Bool {
        observer.shouldSuppressError(for: self, with: info)
    }
}

struct SwiftTestingRetryGroupContext: Sendable {
    typealias Skip = (by: (feature: FeatureId, reason: String)?, status: SkipStatus)
    
    struct Errors {
        let catched: (any Error)?
        let issues: [SwiftTestingIssue]
    }
    
    enum EndAction {
        case skip(reason: String, location: SwiftTestingSourceLocation?)
        case fail
    }
    
    let test: SwiftTestingTestContext
    let skipStrategy: RetryGroupSkipStrategy
    let successStrategy: RetryGroupSuccessStrategy
    
    private(set) var info: TestRunInfoEnd
    private(set) var executions: [(run: SwiftTestingTestRunContext, status: SwiftTestingTestStatus)]
    private var _cancelledByUser: Bool = false
    
    init(test: SwiftTestingTestContext, skip: Skip,
         skipStrategy: RetryGroupSkipStrategy, successStrategy: RetryGroupSuccessStrategy)
    {
        self.test = test
        self.info = .init(skip: skip,
                          retry: (nil, .end(errors: .unsuppressed)),
                          executions: (0, 0))
        self.executions = []
        self.skipStrategy = skipStrategy
        self.successStrategy = successStrategy
    }
    
    var suite: SwiftTestingSuiteContext {
        test.suite
    }
    
    var configuration: SessionConfig {
        test.configuration
    }
    
    var observer: any SwiftTestingObserverType {
        test.observer
    }
    
    var endAction: EndAction? {
        guard !_cancelledByUser else { // special case. User cancelled, we can't recover with logic
            return .none
        }
        guard !_isSkipped else {
            // Find the reason to skip
            switch executions.last(where: { $0.status.isSkipped })?.status {
            case .skipped(feature: _, reason: let reason, issues: _):
                return .skip(reason: reason, location: nil)
            default: return .skip(reason: "unknown skip reason", location: nil)
            }
        }
        guard !_isSucceeded else {
            return .none
        }
        // Check should we fail this group or it already failed by some run.
        return executions.last { $0.status.errorsWereRecorded } == nil ? .fail : .none
    }
    
    private var _isSkipped: Bool {
        switch skipStrategy {
        case .atLeastOneSkipped: return executions.first { $0.status.isSkipped } != nil
        case .allSkipped: return executions.allSatisfy { $0.status.isSkipped }
        }
    }
    
    private var _isSucceeded: Bool {
        switch successStrategy {
        case .alwaysSucceeded: return true
        case .atLeastOneSucceeded: return executions.first { !$0.status.isFailed } != nil
        case .atMostOneFailed: return executions.filter { $0.status.isFailed }.count <= 1
        case .allSucceeded: return executions.filter { $0.status.isFailed }.isEmpty
        }
    }
        
    
    mutating func with(
        run: some SwiftTestingTestRunInfoType,
        performing function: @Sendable (borrowing SwiftTestingTestRunContext, TestRunInfoStart) async -> SwiftTestingTestStatus
    ) async -> Errors? {
        let runInfo = self.info
        let test = self.test
        // Run test
        var (context, retry, status) = await test.withTestRun(named: run.name) { testRun in
            let context = SwiftTestingTestRunContext(testRun: testRun, test: test, info: run)
            if context.info.isParameterized {
                testRun.set(parameters: run.parameters)
            }
            let startInfo = runInfo.toStart
            await test.observer.willStart(testRun: context, with: startInfo)
            let status = await function(context, startInfo)
            let retry = await test.observer.willFinish(testRun: context,
                                                       withStatus: status,
                                                       andInfo: runInfo)
            testRun.set(status: status.testStatus)
            return (context, retry, status)
        }
        // We can't end after Test.cancel in Testing so we ensure that retries are stopped
        if case .skipped(feature: let feature, reason: _, issues: _) = status, feature == .notFeature {
            info.retry = (.notFeature, .end(errors: retry.status.errorsStatus))
            _cancelledByUser = true
        } else {
            info.retry = retry
        }
        
        // Increase executions counts
        info.executions = (total: info.executions.total + 1,
                           failed: status.isFailed ? info.executions.failed + 1 : info.executions.failed)
        
        // Unsuppress errors if asked to do so
        let errors: Errors?
        if !info.retry.status.ignoreErrors {
            switch status.errors {
            case .catched(error: let err, suppressed: true, issues: let issues):
                errors = .init(catched: err, issues: issues)
                status = status.asUnsuppressed
            case .issues(.suppressed(let issues)):
                errors = .init(catched: nil, issues: issues)
                status = status.asUnsuppressed
            default: errors = nil
            }
        } else {
            errors = nil
        }
        
        // Save result
        executions.append((run: context, status: status))
        // Call didFinish with updated info
        await observer.didFinish(testRun: context, with: info)
        // return errors to runner to record them
        return errors
    }
}

struct SwiftTestingTestContext: Sendable {
    typealias GroupResult = (status: SwiftTestingTestStatus,
                             executions: (total: Int, failed: Int))
    
    let suite: SwiftTestingSuiteContext
    let info: any SwiftTestingTestInfoType
    
    var configuration: SessionConfig {
        suite.configuration
    }
    
    var observer: any SwiftTestingObserverType {
        suite.observer
    }
    
    func withTestRun<T>(named name: String, _ action: @Sendable (any TestRun) async throws -> T) async rethrows -> T {
        try await suite.withTestRun(named: name, action)
    }
    
    func withGroup(
        _ function: @Sendable (inout SwiftTestingRetryGroupContext) async -> Void
    ) async -> SwiftTestingRetryGroupContext.EndAction? {
        let (feature, config) = await observer.runGroupConfiguration(test: self)
        var skip: SwiftTestingRetryGroupContext.Skip = (nil, config.skipStatus)
        if let feature = feature, case .skip(let reason, _) = config {
            skip.by = (feature, reason)
        }
        var group = SwiftTestingRetryGroupContext(test: self, skip: skip,
                                                  skipStrategy: config.skipStrategy,
                                                  successStrategy: config.successStrategy)
        await observer.willStart(group: group)
        await function(&group)
        await observer.didFinish(group: group)
        return group.endAction
    }
}

struct SwiftTestingSuiteContext: Sendable {
    final actor State {
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
    let configuration: SessionConfig
    let info: any SwiftTestingTestInfoType
    let observer: any SwiftTestingObserverType
    let testsCount: Int
    
    init(suite: any TestSuite & TestRunProvider,
         configuration: SessionConfig,
         info: any SwiftTestingTestInfoType, testsCount: Int,
         observer: any SwiftTestingObserverType)
    {
        self.init(suite: suite, configuration: configuration,
                  testsCount: testsCount, state: nil,
                  info: info, observer: observer)
    }
   
    init(suite: any TestSuite & TestRunProvider,
         configuration: SessionConfig,
         tests: Set<String>,
         info: any SwiftTestingTestInfoType,
         observer: any SwiftTestingObserverType)
    {
        self.init(suite: suite, configuration: configuration,
                  testsCount: tests.count, state: .init(tests: tests),
                  info: info, observer: observer)
    }
    
    private init(suite: any TestSuite & TestRunProvider,
                 configuration: SessionConfig,
                 testsCount: Int, state: State?,
                 info: any SwiftTestingTestInfoType,
                 observer: any SwiftTestingObserverType)
    {
        self.testsCount = testsCount
        self._state = state
        self._suite = suite
        self.info = info
        self.observer = observer
        self.configuration = configuration
    }
    
    func withTestRun<T>(named name: String, _ action: @Sendable (any TestRun) async throws -> T) async rethrows -> T {
        try await _suite.withActiveTest(named: name, action)
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

struct SwiftTestingSuiteProvider: SwiftTestingSuiteProviderType {
    final actor Registry: SwiftTestingTestRegistryType {
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
    
    final actor State {
        final class ModuleContext {
            let module: any TestModule & TestSuiteProvider
            let config: SessionConfig
            var active: [String: Task<SwiftTestingSuiteContext, any Error>]
            var left: Set<String>
            
            init(module: any TestModule & TestSuiteProvider, config: SessionConfig, left: Set<String>) {
                self.module = module
                self.active = [:]
                self.left = left
                self.config = config
            }
        }
        
        enum ModuleState {
            case notStarted
            case active(ModuleContext)
            case ended
        }
        
        private var _modules: [String: ModuleState] = [:]
        private var _observerAdded: Bool = false
        
        nonisolated let registry: Registry
        nonisolated let observer: any SwiftTestingObserverType
        nonisolated let session: any TestSessionManager
        
        init(session: any TestSessionManager, observer: any SwiftTestingObserverType, registry: Registry) {
            self.session = session
            self.registry = registry
            self.observer = observer
        }
        
        func module(name: String) async throws -> ModuleContext {
            let state = _modules[name, default: .notStarted]
            switch state {
            case .active(let context): return context
            case .ended: throw SwiftTestingRegistryError.moduleAlreadyEnded(name: name)
            case .notStarted: break
            }
            await self._ensureSessionObserver()
            let session = try await self.session.session
            let config = try await self.session.sessionConfig
            let suites = try await self.registry.suites(for: name)
            if case .active(let context) = _modules[name] {
                // other thread created it
                return context
            }
            let module = session.module(named: name)
            let context = ModuleContext(module: module, config: config, left: suites)
            _modules[name] = .active(context)
            await observer.willStart(module: context.module, with: context.config)
            return context
        }
        
        func suite(named suite: String, in module: String,
                   factory: @Sendable @escaping (any TestModule & TestSuiteProvider,
                                                 SessionConfig) async throws ->  SwiftTestingSuiteContext
        ) async throws -> (suite: SwiftTestingSuiteContext, isNew: Bool) {
            let module = try await self.module(name: module)
            if let suite = module.active[suite] {
                return try await (suite.value, false)
            }
            let task = Task { try await factory(module.module, module.config) }
            module.active[suite] = task
            module.left.remove(suite)
            return try await (task.value, true)
        }
        
        func didEnded(suite: any TestSuite) async throws -> (Bool, SwiftTestingSuiteContext?) {
            guard case .active(let context) = _modules[suite.module.name] else {
                throw SwiftTestingRegistryError.moduleAlreadyEnded(name: suite.module.name)
            }
            context.active.removeValue(forKey: suite.name)
            if context.left.isEmpty && context.active.isEmpty {
                _modules[suite.module.name] = .ended
                return (true, nil)
            }
            return try await (false, context.active.first?.value.value)
        }
        
        private func _ensureSessionObserver() async {
            if !_observerAdded {
                _observerAdded = true
                await self.session.add(observer: observer)
            }
        }
    }
    
    var registry: any SwiftTestingTestRegistryType { _state.registry }
    var observer: any SwiftTestingObserverType { _state.observer }
    private let _state: State
    
    init(session: any TestSessionManager, observer: any SwiftTestingObserverType) {
        self._state = .init(session: session, observer: observer, registry: Registry())
    }
    
    func with(suite info: some SwiftTestingTestInfoType,
              performing function: @Sendable (borrowing SwiftTestingSuiteContext) async throws -> Void) async throws
    {
        let suite = try await self._state.suite(named: info.suite, in: info.module) { (mod, config) in
            let count = try await self.registry.count(for: info)
            let suite = mod.startSuite(named: info.suite, at: nil, framework: "Testing")
            return .init(suite: suite, configuration: config, info: info,
                         testsCount: count, observer: self.observer)
        }
        if suite.isNew {
            await observer.willStart(suite: suite.suite)
        }
        try await with(context: suite.suite, performing: function)
    }
    
    func with(virtual test: some SwiftTestingTestInfoType,
              performing function: @Sendable (borrowing SwiftTestingSuiteContext) async throws -> Void) async throws
    {
        let suite = try await self._state.suite(named: test.suite, in: test.module) { (mod, config) in
            let tests = try await self.registry.tests(for: test)
            let suite = mod.startSuite(named: test.suite, at: nil, framework: "Testing")
            return SwiftTestingSuiteContext(suite: suite, configuration: config,
                                            tests: tests, info: test, observer: self.observer)
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
            if await context.end() { // if suite ended (no tests left)
                let (ended, active) = try await _state.didEnded(suite: context.suite)
                await observer.didFinish(suite: context, active: active)
                if ended { // if module ended (no suites left)
                    context.suite.module.end()
                    await observer.didFinish(module: context.suite.module, with: context.configuration)
                }
            }
        }
    }
    
    var session: any TestSessionManager {
        _state.session
    }
}

extension SwiftTestingTestStatus {
    var suppressedErrors: SwiftTestingRetryGroupContext.Errors? {
        switch self.errors {
        case .catched(error: let error, suppressed: true, issues: let issues):
            return .init(catched: error, issues: issues)
        case .issues(.suppressed(let issues)):
            return .init(catched: nil, issues: issues)
        default: return nil
        }
    }
}

extension Optional where Wrapped == SwiftTestingTestStatus.Errors {
    mutating func add(issue: SwiftTestingIssue, suppress: @autoclosure () -> Bool) -> Bool {
        switch self {
        case .none:
            let res = suppress()
            self = .some(.issues(res ? .suppressed([issue]) : .unsuppressed([issue])))
            return res
        case .some(var errors):
            let res = errors.add(issue: issue)
            self = .some(errors)
            return res
        }
    }
    
    mutating func catched(error: any Error, suppress: @autoclosure () -> Bool) {
        switch self {
        case .none:
            self = .some(.catched(error: error, suppressed: suppress(), issues: []))
        case .some(var errors):
            errors.catched(error: error)
            self = .some(errors)
        }
    }
}

extension Array where Element == SwiftTestingIssue {
    func recordAll(test location: SwiftTestingSourceLocation) {
        forEach { $0.record(test: location) }
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
