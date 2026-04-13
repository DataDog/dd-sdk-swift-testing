/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import Testing

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

enum SwiftTestingIssueKind {
    case unconditional
    case expectation(description: String)
    case error(any Error)
    case confirmationMiscounted(actual: Int, expected: any RangeExpression & Sendable)
    case timeLimitExceeded(timeLimitComponents: (seconds: Int64, attoseconds: Int64))
    case knownIssueNotRecorded
    case valueAttachmentFailed(_ error: any Error)
    case apiMisused
    case system
    case unknown(String)
    
    func asTypeAndMessage(warning: Bool, comment: String?) -> (type: String, message: String?) {
        let type = warning ? "Warning" : "Error"
        switch self {
        case .unconditional: return (type, comment)
        case .apiMisused: return ("\(type)[ApiMisused]", comment)
        case .expectation(description: let description):
            return ("\(type)[ExpectationFailed]", combine(message: description, comment: comment))
        case .confirmationMiscounted(actual: let actual, expected: let expected):
            return ("\(type)[ConfirmationMiscounted]", combine(message: "actual: \(actual), expected: \(expected)",
                                                               comment: comment))
        case .timeLimitExceeded(timeLimitComponents: let limit):
            return ("\(type)[TimeLimitExceeded]", combine(message: "\(limit)", comment: comment))
        case .knownIssueNotRecorded: return ("\(type)[KnownIssueNotRecorded]", comment)
        case .valueAttachmentFailed(let error):
            return ("\(type)[ValueAttachmentFailed]", combine(message: "\(error)", comment: comment))
        case .system: return ("\(type)[System]", comment)
        case .unknown(let error): return ("\(type)[Unknown]", combine(message: error, comment: comment))
        case .error(let error):
            return ("\(type)[\(String(reflecting: Swift.type(of: error)))]", combine(message: "\(error)",
                                                                                     comment: comment))
        }
    }
    
    private func combine(message: String, comment: String?) -> String {
        guard let comment else { return message }
        return message + " - " + comment
    }
}

protocol SwiftTestingIssue: Sendable {
    var issueKind: SwiftTestingIssueKind { get }
    var comment: String? { get }
    var isWarning: Bool { get }
    var location: SwiftTestingSourceLocation? { get }
    func record(test location: SwiftTestingSourceLocation)
}

extension SwiftTestingIssue {
    var asTestError: TestError {
        let info = issueKind.asTypeAndMessage(warning: isWarning,
                                              comment: comment)
        var stack: String? = nil
        if let location {
            stack = "\(location.filePath):\(location.line):\(location.column)"
        }
        return .init(type: info.type, message: info.message, stack: stack)
    }
}

enum SwiftTestingTestStatus: Sendable {
    enum Issues {
        case suppressed([SwiftTestingIssue])
        case unsuppressed([SwiftTestingIssue])
        
        var issues: [SwiftTestingIssue] {
            switch self {
            case .suppressed(let i), .unsuppressed(let i):
                return i
            }
        }
    }
    
    enum Errors {
        case catched(error: any Error, suppressed: Bool, issues: [SwiftTestingIssue])
        case issues(Issues)
        
        var issues: Issues {
            switch self {
            case .issues(let issues): return issues
            case .catched(error: _, suppressed: true, issues: let issues):
                return .suppressed(issues)
            case .catched(error: _, suppressed: false, issues: let issues):
                return .unsuppressed(issues)
            }
        }
        
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
        
        var asUnsuppressed: Self {
            switch self {
            case .catched(error: let err, suppressed: true, issues: let isues):
                return .catched(error: err, suppressed: false, issues: isues)
            case .issues(.suppressed(let issues)):
                return .issues(.unsuppressed(issues))
            default: return self
            }
        }
    }
    
    case skipped(feature: FeatureId, reason: String, issues: Issues?)
    case cancelled(error: any Error, issues: Issues?)
    case failed(Errors)
    case passed
    
    var testStatus: TestStatus {
        switch self {
        case .skipped, .cancelled: return .skip
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
        case .skipped, .cancelled: return true
        default: return false
        }
    }
    
    var errors: Errors? {
        switch self {
        case .failed(let errors): return errors
        case .skipped(feature: _, reason: _, issues: let issues),
             .cancelled(error: _, issues: let issues):
            return issues.map { .issues($0) }
        default: return nil
        }
    }
    
    var errorsWereRecorded: Bool {
        switch self {
        case .failed(.catched(error: _, suppressed: false, issues: _)): return true
        case .failed(.issues(.unsuppressed(_))): return true
        case .skipped(feature: _, reason: _, issues: .unsuppressed(_)): return true
        case .cancelled(error: _, issues: .unsuppressed(_)): return true
        default: return false
        }
    }
    
    var asUnsuppressed: Self {
        switch self {
        case .skipped(feature: let feat, reason: let reas, issues: .suppressed(let issues)):
            return .skipped(feature: feat, reason: reas, issues: .unsuppressed(issues))
        case .cancelled(error: let error, issues: .suppressed(let issues)):
            return .cancelled(error: error, issues: .unsuppressed(issues))
        case .failed(let errs): return .failed(errs.asUnsuppressed)
        default: return self
        }
    }
    
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
        case cancel(error: any Error)
        case fail
    }
    
    let test: SwiftTestingTestContext
    let successStrategy: RetryGroupSuccessStrategy
    
    private(set) var skipStrategy: RetryGroupSkipStrategy
    private(set) var info: TestRunInfoEnd
    private(set) var executions: [(run: SwiftTestingTestRunContext, status: SwiftTestingTestStatus)]
    
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
        guard !isSkipped else {
            // Find the reason to skip
            switch executions.last(where: { $0.status.isSkipped })?.status {
            case .cancelled(error: let error, issues: _):
                return .cancel(error: error)
            case .skipped(feature: _, reason: let reason, issues: _):
                return .skip(reason: reason, location: nil)
            default: return .skip(reason: "unknown skip reason", location: nil)
            }
        }
        guard !isSucceeded else {
            return .none
        }
        // Check should we fail this group or it is already failed by some run.
        return executions.last { $0.status.errorsWereRecorded } == nil ? .fail : .none
    }
    
    var isSkipped: Bool {
        switch skipStrategy {
        case .atLeastOneSkipped: return executions.last { $0.status.isSkipped } != nil
        case .allSkipped: return executions.allSatisfy { $0.status.isSkipped }
        }
    }
    
    var isSucceeded: Bool {
        switch successStrategy {
        case .alwaysSucceeded: return true
        case .atLeastOneSucceeded: return executions.last { !$0.status.isFailed } != nil
        case .atMostOneFailed: return executions.filter { $0.status.isFailed }.count <= 1
        case .allSucceeded: return executions.filter { $0.status.isFailed }.isEmpty
        }
    }
    
    var status: TestStatus {
        isSkipped ? .skip : isSucceeded ? .pass : .fail
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
            // Add errors to the test.
            if let issues = status.errors?.issues.issues {
                for issue in issues {
                    testRun.add(error: issue.asTestError)
                }
            }
            // set test status
            testRun.set(status: status.testStatus)
            return (context, retry, status)
        }
        // We can't end after Test.cancel in Testing so we ensure that retries are stopped
        if case .cancelled = status {
            info.retry = (.notFeature, .end(errors: retry.status.errorsStatus))
            // enforce skip by changing strategy
            skipStrategy = .atLeastOneSkipped
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

final class SwiftTestingTestContext: Sendable {
    typealias GroupResult = (status: SwiftTestingTestStatus,
                             executions: (total: Int, failed: Int))
    
    let suite: SwiftTestingSuiteContext
    let info: any SwiftTestingTestInfoType
    // It's ok to be unsafe. We update it once and it's a serial access
    nonisolated(unsafe) var status: TestStatus
    
    var configuration: SessionConfig {
        suite.configuration
    }
    
    var observer: any SwiftTestingObserverType {
        suite.observer
    }
    
    init(suite: SwiftTestingSuiteContext, info: any SwiftTestingTestInfoType) {
        self.suite = suite
        self.info = info
        self.status = .pass
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
        status = group.status
        return group.endAction
    }
}

struct SwiftTestingSuiteContext: Sendable {
    final actor State {
        private var _statuses: [String: TestStatus]
        private var _left: Set<String>
        
        var isEnded: Bool { _left.isEmpty }
        
        init(tests: Set<String>) {
            self._left = tests
            self._statuses = [:]
        }
        
        var statuses: [String: TestStatus]? {
            isEnded ? _statuses : nil
        }
        
        func end(test: some SwiftTestingTestInfoType, status: TestStatus) {
            _left.remove(test.name)
            _statuses[test.name] = status
        }
    }
    
    private let _state: State
    private let _suite: any TestSuite & TestRunProvider
    
    var suite: any TestSuite { _suite }
    let configuration: SessionConfig
    let info: any SwiftTestingTestInfoType
    let observer: any SwiftTestingObserverType
    let moduleManager: any TestModuleManager
    let testsCount: Int
    
    init(suite: any TestSuite & TestRunProvider,
         configuration: SessionConfig,
         info: any SwiftTestingTestInfoType,
         testsCount: Int,
         observer: any SwiftTestingObserverType,
         moduleManager: any TestModuleManager)
    {
        self.init(suite: suite, configuration: configuration,
                  testsCount: testsCount, state: .init(tests: []),
                  info: info, observer: observer, moduleManager: moduleManager)
    }
   
    init(suite: any TestSuite & TestRunProvider,
         configuration: SessionConfig,
         tests: Set<String>,
         info: any SwiftTestingTestInfoType,
         observer: any SwiftTestingObserverType,
         moduleManager: any TestModuleManager)
    {
        self.init(suite: suite, configuration: configuration,
                  testsCount: tests.count, state: .init(tests: tests),
                  info: info, observer: observer, moduleManager: moduleManager)
    }
    
    private init(suite: any TestSuite & TestRunProvider,
                 configuration: SessionConfig,
                 testsCount: Int, state: State,
                 info: any SwiftTestingTestInfoType,
                 observer: any SwiftTestingObserverType,
                 moduleManager: any TestModuleManager)
    {
        self.testsCount = testsCount
        self._state = state
        self._suite = suite
        self.info = info
        self.observer = observer
        self.configuration = configuration
        self.moduleManager = moduleManager
    }
    
    func withTestRun<T>(named name: String, _ action: @Sendable (any TestRun) async throws -> T) async rethrows -> T {
        try await _suite.withActiveTest(named: name, action)
    }
    
    func end() async -> Bool {
        guard let statuses = await _state.statuses else {
            // we have more tests to run
            return false
        }
        // no more tests. we can end
        if statuses.values.allSatisfy({ $0 == .skip }) {
            _suite.set(skipped: nil)
        } else if statuses.values.contains(where: { $0 == .fail }) {
            _suite.set(failed: nil)
        }
        await observer.willFinish(suite: self)
        _suite.end()
        return true
    }
    
    func with(test: some SwiftTestingTestInfoType,
              performing function: @Sendable (borrowing SwiftTestingTestContext) async throws -> Void) async throws
    {
        let context = SwiftTestingTestContext(suite: self, info: test)
        await observer.willStart(test: context)
        var catched: (any Error)? = nil
        do {
            try await function(context)
        } catch {
            catched = error
            // Fail it if we got an error on top of the test (from some scope provider)
            if context.status == .pass {
                context.status = error.isSwiftTestingSkip ? .skip : .fail
            }
        }
        await observer.didFinish(test: context)
        await _state.end(test: test, status: context.status)
        // rethrow error
        if let catched { throw catched }
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
            let manager: any TestModuleManager
            let config: SessionConfig
            var active: [String: Task<SwiftTestingSuiteContext, any Error>]
            var left: Set<String>
            
            init(module: any TestModule & TestSuiteProvider,
                 manager: any TestModuleManager,
                 config: SessionConfig, left: Set<String>)
            {
                self.module = module
                self.active = [:]
                self.left = left
                self.config = config
                self.manager = manager
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
            let (session, config) = try await self.session.sessionAndConfig
            let suites = try await self.registry.suites(for: name)
            if case .active(let context) = _modules[name] {
                // other thread created it
                return context
            }
            let module = session.module(named: name)
            let context = ModuleContext(module: module, manager: session, config: config, left: suites)
            _modules[name] = .active(context)
            return context
        }
        
        func suite(named suite: String, in module: String,
                   factory: @Sendable @escaping (any TestModule & TestSuiteProvider,
                                                 any TestModuleManager,
                                                 SessionConfig) async throws ->  SwiftTestingSuiteContext
        ) async throws -> (suite: SwiftTestingSuiteContext, isNew: Bool) {
            let module = try await self.module(name: module)
            if let suite = module.active[suite] {
                return try await (suite.value, false)
            }
            let task = Task { try await factory(module.module, module.manager, module.config) }
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
        let suite = try await self._state.suite(named: info.suite, in: info.module) { (mod, manager, config) in
            let count = try await self.registry.count(for: info)
            let suite = mod.startSuite(named: info.suite, at: nil, framework: Self.framework)
            return .init(suite: suite, configuration: config, info: info,
                         testsCount: count, observer: self.observer, moduleManager: manager)
        }
        if suite.isNew {
            await observer.willStart(suite: suite.suite)
        }
        try await with(context: suite.suite, performing: function)
    }
    
    func with(virtual test: some SwiftTestingTestInfoType,
              performing function: @Sendable (borrowing SwiftTestingSuiteContext) async throws -> Void) async throws
    {
        let suite = try await self._state.suite(named: test.suite, in: test.module) { (mod, manager, config) in
            let tests = try await self.registry.tests(for: test)
            let suite = mod.startSuite(named: test.suite, at: nil, framework: Self.framework)
            return SwiftTestingSuiteContext(suite: suite, configuration: config,
                                            tests: tests, info: test, observer: self.observer,
                                            moduleManager: manager)
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
                let (modEnded, active) = try await _state.didEnded(suite: context.suite)
                await observer.didFinish(suite: context, active: active)
                if modEnded { // if module ended (no suites left)
                    context.moduleManager.end(module: context.suite.module)
                }
            }
        }
    }
    
    var session: any TestSessionManager {
        _state.session
    }
    
    static let framework = "Testing"
}

extension TestSuite {
    var isSwiftTesting: Bool { testFramework ==  SwiftTestingSuiteProvider.framework }
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
