/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

#if canImport(Testing)
import Testing

public struct DatadogSwiftTestingTrait: TestTrait, SuiteTrait {
    public typealias TestScopeProvider = DatadogSwiftTestingScopeProvider
    
    public let isRecursive: Bool = true
    private let _provider: (any SwiftTestingSuiteProviderType)?
    private let _actions: any DatadogSwiftTestingTestActions
    
    init(provider: (any SwiftTestingSuiteProviderType)? = nil,
         actions: any DatadogSwiftTestingTestActions = TestScopeProvider.Actions())
    {
        self._provider = provider
        self._actions = actions
    }
    
    public func prepare(for test: Testing.Test) async throws {
        try await prepare(test: TestScopeProvider.SwiftTest(test: test))
    }
    
    public func scopeProvider(for test: Testing.Test, testCase: Testing.Test.Case?) -> TestScopeProvider? {
        guard let provider = _activeProvider else {
            return nil
        }
        return TestScopeProvider(provider: provider, actions: _actions)
    }
    
    func prepare(test: some SwiftTestingTestInfoType) async throws {
        await _activeProvider?.registry.register(test: test)
    }
    
    private var _activeProvider: (any SwiftTestingSuiteProviderType)? {
        _provider ?? Self.sharedSuiteProvider
    }
    
    static var sharedSuiteProvider: (any SwiftTestingSuiteProviderType)? = nil
}

public struct DatadogSwiftTestingScopeProvider: TestScoping {
    private let _provider: any SwiftTestingSuiteProviderType
    private let _actions: any DatadogSwiftTestingTestActions
    
    init(provider: any SwiftTestingSuiteProviderType, actions: any DatadogSwiftTestingTestActions) {
        self._provider = provider
        self._actions = actions
    }
    
    public func provideScope(for test: Testing.Test, testCase: Testing.Test.Case?,
                             performing function: @Sendable () async throws -> Void) async throws
    {
        let testId = TestID(test: test, testCase: testCase)
        // check that scope was not applied to this test/testCase.
        // it can happen if we have two .datadogTesting traits applied to
        // nested suites or suite and test
        guard Self.lastTestTraitApplied != testId else {
            return try await function()
        }
        // save testId to the scope so we can check it
        try await Self.$lastTestTraitApplied.withValue(testId) {
            if let testCase {
                // This is a concrete test run
                try await provideScope(run: SwiftTestRun(test: test, testCase: testCase),
                                       performing: function)
            } else if test.isSuite {
                // This is a suite
                try await provideScope(suite: SwiftTest(test: test), performing: function)
            } else {
                // Test scope
                try await provideScope(test: SwiftTest(test: test), performing: function)
            }
        }
    }
    
    func provideScope(suite: some SwiftTestingTestInfoType, performing function: @Sendable () async throws -> Void) async throws {
        try await _provider.with(suite: suite) { suite in
            try await Self.$datadogSuite.withValue(suite, operation: function)
        }
    }
    
    func provideScope(test: some SwiftTestingTestInfoType, performing function: @Sendable () async throws -> Void) async throws {
        if let suite = Self.datadogSuite {
            return try await suite.with(test: test) { test in
                try await Self.$datadogTest.withValue(test, operation: function)
            }
        }
        try await _provider.with(virtual: test) { suite in
            try await suite.with(test: test) { test in
                try await Self.$datadogTest.withValue(test, operation: function)
            }
        }
    }
    
    func provideScope(run: some SwiftTestingTestRunInfoType, performing function: @Sendable () async throws -> Void) async throws {
        guard let test = Self.datadogTest else {
            return try await function()
        }
        let action = await test.withGroup { group in
            // Thread safe structure to collect errors.
            // Put it here so mutex will not be recreated every run
            let errors: Synced<SwiftTestingTestStatus.Errors?> = .init(nil)
            repeat {
                let restoredErrors = await group.with(run: run) { run, runInfo in
                    // Skip logic. We need it to create skipped test run
                    if let skip = runInfo.skip.by {
                        return .skipped(feature: skip.feature,
                                        reason: skip.reason,
                                        issues: errors.value?.issues)
                    }
                    // Normal logic. Run test, suppress errors if needed
                    do {
                        try await withKnownIssue(isIntermittent: true) {
                            try await function()
                        } matching: { issue in
                            errors.update {
                                $0.add(issue: issue,
                                       suppress: run.shouldSuppressError(info: runInfo))
                            }
                        }
                    } catch {
                        // we can't use Testing.SkipInfo directly so we will use runtime to detect it
                        if error.isSwiftTestingSkip {
                            return .cancelled(error: error, issues: errors.value?.issues)
                        } else {
                            errors.update {
                                $0.catched(error: error,
                                           suppress: run.shouldSuppressError(info: runInfo))
                            }
                        }
                    }
                    if let errorsValue = errors.value {
                        return .failed(errorsValue)
                    }
                    return .passed
                }
                // clear issues. They are added to the status
                errors.update { $0 = nil }
                // Restore errors if needed
                if let restoredErrors {
                    restoredErrors.recordAll(test: run.location)
                }
            } while group.info.retry.status.isRetry
        }
        switch action {
        case .some(.skip(reason: let reason, location: let location)):
            try _actions.cancel(reason: reason, location: location ?? run.location)
        case .some(.cancel(error: let error)): throw error
        case .some(.fail):
            _actions.fail(reason: "\(run.suite).\(run.name) failed", location: run.location)
        case .none: break
        }
    }
    
    @TaskLocal static var datadogSuite: SwiftTestingSuiteContext? = nil
    @TaskLocal static var datadogTest: SwiftTestingTestContext? = nil
    @TaskLocal static var lastTestTraitApplied: TestID? = nil
}

protocol DatadogSwiftTestingTestActions: Sendable {
    func cancel(reason: String, location: SwiftTestingSourceLocation) throws
    func fail(reason: String, location: SwiftTestingSourceLocation)
}

extension Testing.Trait where Self == DatadogSwiftTestingTrait {
    public static var datadogTesting: Self { Self() }
}

extension DatadogSwiftTestingScopeProvider {
    struct SwiftTest: SwiftTestingTestInfoType {
        let test: Testing.Test
        let name: String
        let suite: String
        
        init(test: Testing.Test) {
            self.test = test
            self.name = test.ddName
            self.suite = test.ddSuite
        }
        
        var module: String { test.ddModule }
        var isSuite: Bool { test.isSuite }
        var hasSuite: Bool { test.ddHasSuite }
        var isParameterized: Bool { test.isParameterized }
        var attachedTags: any TestTags { test.attachedTags }
    }
    
    struct SwiftTestRun: SwiftTestingTestRunInfoType {
        let test: Testing.Test
        let testCase: Testing.Test.Case
        let name: String
        let suite: String
        
        init(test: Testing.Test, testCase: Testing.Test.Case) {
            self.test = test
            self.testCase = testCase
            self.name = test.ddName
            self.suite = test.ddSuite
        }
        
        var module: String { test.ddModule }
        var isSuite: Bool { test.isSuite }
        var hasSuite: Bool { test.ddHasSuite }
        var isParameterized: Bool { testCase.isParameterized }
        var location: SwiftTestingSourceLocation { test.sourceLocation.asDD }
        var attachedTags: any TestTags { test.attachedTags }

        var parameters: TestRunParameters {
            // Skip the Mirror walk entirely for non-parameterized cases —
            // `ddArguments` would return `nil` anyway, but `isParameterized`
            // is cheap and avoids the reflection on the hot path.
            guard isParameterized, let args = testCase.ddArguments else {
                return .init(arguments: .nil, metadata: nil)
            }
            let mapped: [JSONGeneric] = args.map {
                .object(["name": .string($0.name), "value": .string($0.value), "type": .string($0.type)])
            }
            return .init(arguments: .array(mapped), metadata: nil)
        }
    }
    
    struct Actions: DatadogSwiftTestingTestActions {
        func cancel(reason: String, location: SwiftTestingSourceLocation) throws {
#if compiler(>=6.3)
            try Testing.Test.cancel(Comment(rawValue: reason),
                                    sourceLocation: location.asSwift)
#endif
        }
        
        func fail(reason: String, location: SwiftTestingSourceLocation) {
            Issue.record(Comment(rawValue: reason), sourceLocation: location.asSwift)
        }
    }
    
    struct TestID: Equatable, Sendable {
        let test: Testing.Test.ID
        let testCase: CaseID?

        init(test: borrowing Testing.Test, testCase: borrowing Testing.Test.Case?) {
            self.test = test.id
            self.testCase = testCase.map { $0.ddID }
        }
    }

    /// Mirror-derived shadow of `Testing.Test.Case.ID`.
    ///
    /// `Test.Case.ID`, `Test.Case.arguments`, `Test.Case.discriminator`, and
    /// `Test.Case.isStable` are all marked `@_spi(ForToolsIntegrationOnly)` —
    /// not usable from regular client code. `Test.Case` stores everything we
    /// need in a single private property `_kind: _Kind` (an enum with
    /// `.nonParameterized` and `.parameterized(arguments:, discriminator:,
    /// isStable:)`). We walk `Mirror(reflecting: testCase)` to read those
    /// values without taking the SPI dependency, then reconstruct the same
    /// `(argumentIDs, discriminator, isStable)` triple Swift Testing uses for
    /// `Test.Case.ID`. Equality / hashing mirrors `Test.Case.ID`'s own.
    ///
    /// If a future Swift Testing release reshapes `_kind`, the Mirror walk
    /// degrades to `(nil, nil, true)`. That matches a non-parameterized case
    /// and would cause parameterized cases of the same test to share a
    /// `TestID` — `SwiftTestingTraitTests.testParameterized(p1:p2:)`
    /// (expects three independent runs) is the canary for that regression.
    struct CaseID: Equatable, Hashable, Sendable {
        /// Raw bytes of each `Test.Case.Argument.ID`, in the order they
        /// appear in `Test.Case.arguments`. `nil` for non-parameterized cases.
        let argumentIDs: [[UInt8]]?
        /// Distinguishes cases that share `argumentIDs` (e.g.
        /// `@Test(arguments: [1, 1])`). `nil` for non-parameterized cases.
        let discriminator: Int?
        /// Whether Swift Testing was able to derive a stable encoded
        /// representation of every argument; mirrors `Test.Case.ID.isStable`.
        let isStable: Bool
    }
}

extension Testing.Test.Case {
    /// Mirror-extracted argument-id bytes. `nil` for non-parameterized cases.
    /// Expected layout: `_kind.parameterized(arguments: [Argument], …)` where
    /// each `Argument.id.bytes` is `[UInt8]`. Returns `nil` if any step of
    /// that walk fails so a layout drift surfaces as a uniform `nil` (caught
    /// by `testParameterized`).
    var ddArgumentIDs: [[UInt8]]? {
        guard let arguments = ddKindAssociatedValue(named: "arguments") else { return nil }
        var ids: [[UInt8]] = []
        for argChild in Mirror(reflecting: arguments).children {
            guard let bytes = Mirror(reflecting: argChild.value).descendant("id", "bytes") as? [UInt8]
            else { return nil }
            ids.append(bytes)
        }
        return ids
    }

    /// `Test.Case.discriminator`, extracted via `Mirror`. `nil` for
    /// non-parameterized cases.
    var ddDiscriminator: Int? {
        ddKindAssociatedValue(named: "discriminator") as? Int
    }

    /// `Test.Case.isStable`, extracted via `Mirror`. Defaults to `true` for
    /// non-parameterized cases (which Swift Testing also treats as stable).
    var ddIsStable: Bool {
        (ddKindAssociatedValue(named: "isStable") as? Bool) ?? true
    }

    /// Mirror-derived equivalent of `Test.Case.ID`, safe to use as a hash key.
    var ddID: DatadogSwiftTestingScopeProvider.CaseID {
        .init(argumentIDs: ddArgumentIDs,
              discriminator: ddDiscriminator,
              isStable: ddIsStable)
    }

    /// Mirror-extracted argument metadata, one entry per argument in
    /// declaration order. Each entry carries:
    ///
    ///   - `value`: `String(reflecting:)` of the argument value. Strings come
    ///     back quoted (`"\"hello\""`) to match the encoding `SwiftTestRun`
    ///     was previously deriving from `String(describing: testCase)`.
    ///   - `name`: parameter `firstName`, joined with `secondName` by a
    ///     space when the second name is present (e.g. `"for count"`).
    ///   - `type`: fully-qualified type name (e.g. `"Swift.Int"`), derived
    ///     by walking `TypeInfo._kind` — `TypeInfo` itself is also
    ///     `@_spi(ForToolsIntegrationOnly)` and can't be named directly.
    ///
    /// Returns `nil` for non-parameterized cases or when the Mirror walk
    /// fails.
    var ddArguments: [DDArgument]? {
        guard let arguments = ddKindAssociatedValue(named: "arguments") else { return nil }
        var result: [DDArgument] = []
        for argChild in Mirror(reflecting: arguments).children {
            guard let argument = Self.ddExtractArgument(from: argChild.value) else { return nil }
            result.append(argument)
        }
        return result
    }

    private static func ddExtractArgument(from any: Any) -> DDArgument? {
        let argMirror = Mirror(reflecting: any)
        guard let value = argMirror.descendant("value"),
              let parameterAny = argMirror.descendant("parameter")
        else { return nil }
        let paramMirror = Mirror(reflecting: parameterAny)
        guard let firstName = paramMirror.descendant("firstName") as? String else { return nil }

        var name = firstName
        // `secondName` is `Optional<String>`
        if let secondName = (paramMirror.descendant("secondName") as? String?).flatMap({$0}) {
            name = "\(firstName) \(secondName)"
        }

        let type = paramMirror.descendant("typeInfo").flatMap(Self.ddExtractTypeName(from:)) ?? "<unknown>"
        return DDArgument(value: String(reflecting: value), name: name, type: type)
    }

    /// Walks a `Testing.TypeInfo` value via `Mirror` to recover its fully-
    /// qualified name without depending on the SPI type. `TypeInfo._kind` is
    /// either `.type(Any.Type)` (for which `String(reflecting:)` yields the
    /// module-prefixed name) or `.nameOnly(fullyQualifiedComponents: [String],
    /// …)` (for which we join the components with `.`).
    private static func ddExtractTypeName(from typeInfo: Any) -> String? {
        let mirror = Mirror(reflecting: typeInfo)
        guard let kind = mirror.descendant("_kind") else { return nil }
        let kindMirror = Mirror(reflecting: kind)
        guard kindMirror.displayStyle == .enum,
              let child = kindMirror.children.first
        else { return nil }
        switch child.label {
        case "type": return String(reflecting: child.value)
        case "nameOnly":
            let assoc = Mirror(reflecting: child.value)
            return (assoc.descendant("fullyQualifiedComponents") as? [String])?
                .joined(separator: ".")
        default:
            return nil
        }
    }

    /// Walks `Mirror(self)` → `_kind` → the labelled element of the
    /// `.parameterized(...)` case's associated-values tuple matching `name`.
    /// Returns `nil` for `.nonParameterized` or any layout mismatch.
    private func ddKindAssociatedValue(named name: String) -> Any? {
        guard isParameterized, let kind = Mirror(reflecting: self).descendant("_kind") else { return nil }
        let kindMirror = Mirror(reflecting: kind)
        guard kindMirror.displayStyle == .enum,
              let parameterized = kindMirror.children.first(where: { $0.label == "parameterized" })
        else { return nil }
        return Mirror(reflecting: parameterized.value)
            .children
            .first(where: { $0.label == name })?
            .value
    }

    struct DDArgument: Sendable {
        let value: String
        let name: String
        let type: String
    }
}

extension Testing.Test {
    /// Module identifier used by the registry, module manager, and span tags.
    /// Underscores are normalized to hyphens so that Swift Testing's
    /// `id.moduleName` (e.g. `"My_Tests"`) and XCTest's `Bundle.name` (e.g.
    /// `"My-Tests"`) collapse to the same canonical name. Without this both
    /// framework paths produce two `Module` instances for the same bundle.
    var ddModule: String {
        id.moduleName.replacingOccurrences(of: "_", with: "-")
    }


    var ddHasSuite: Bool {
        let components = id.nameComponents
        return components.count > 1 || components.first?.last != ")"
    }
    
    var ddName: String {
        if name.hasSuffix("()") {
            return String(name[..<name.index(name.endIndex, offsetBy: -2)])
        }
        return name
    }
    
    var ddSuite: String {
        let components = id.nameComponents
        // For test functions, the trailing component is the function signature
        // (ends with ")"). Drop it to obtain the enclosing type chain. For
        // suite Tests every component is a type name and is kept. Nested
        // types produce a dotted chain like "Outer.Inner".
        let typeChain = isSuite || components.last?.last != ")"
            ? components
            : Array(components.dropLast())
        guard !typeChain.isEmpty else {
            return "[\(sourceLocation.fileName.replacingOccurrences(of: ".swift", with: ""))]"
        }
        return typeChain.joined(separator: ".")
    }
}

extension Issue: SwiftTestingIssue {
    var issueKind: SwiftTestingIssueKind {
        switch kind {
        case .expectationFailed:
            return .expectation(description: "\(kind)")
        case .apiMisused: return .apiMisused
        case .confirmationMiscounted(actual: let actual, expected: let expected):
            return .confirmationMiscounted(actual: actual, expected: expected)
        case .errorCaught(let error): return .error(error)
        case .knownIssueNotRecorded: return .knownIssueNotRecorded
        case .timeLimitExceeded(timeLimitComponents: let time):
            return .timeLimitExceeded(timeLimitComponents: time)
        case .valueAttachmentFailed(let err): return .valueAttachmentFailed(err)
        case .system: return .system
        case .unconditional: return .unconditional
        @unknown default: return .unknown("\(kind)")
        }
    }
    
    var comment: String? {
        guard !comments.isEmpty else { return nil }
        return comments.map { $0.rawValue }.joined(separator: "\n")
    }

#if compiler(>=6.3)
    var isWarning: Bool { !isFailure }
#else
    var isWarning: Bool { false }
#endif
    
    var location: SwiftTestingSourceLocation? { sourceLocation?.asDD }
    
    func record(test location: SwiftTestingSourceLocation) {
        let info = issueKind.asTypeAndMessage(warning: isWarning, comment: comment)
        let message = info.message.map { "\(info.type): \($0)" } ?? info.type
        if let error = error {
            Issue.record(error, Comment(rawValue: message),
                         sourceLocation: sourceLocation ?? location.asSwift)
        } else {
#if compiler(>=6.3)
            Issue.record(Comment(rawValue: message),
                         severity: severity,
                         sourceLocation: sourceLocation ?? location.asSwift)
#else
            Issue.record(Comment(rawValue: message),
                         sourceLocation: sourceLocation ?? location.asSwift)
#endif
        }
    }
}

extension SourceLocation {
    var asDD: SwiftTestingSourceLocation {
#if compiler(>=6.3)
        .init(fileID: self.fileID, filePath: self.filePath, line: self.line, column: self.column)
#else
        .init(fileID: self.fileID, filePath: self._filePath, line: self.line, column: self.column)
#endif
    }
}

extension SwiftTestingSourceLocation {
    var asSwift: SourceLocation {
        .init(fileID: self.fileID, filePath: self.filePath, line: self.line, column: self.column)
    }
}

extension SwiftTestingRetryGroupContext.Errors {
    func recordAll(test location: SwiftTestingSourceLocation) {
        self.issues.recordAll(test: location)
        if let catched {
            Issue.record(catched, sourceLocation: location.asSwift)
        }
    }
}

extension Error {
    var isSwiftTestingSkip: Bool {
        String(reflecting: type(of: self)) == "Testing.SkipInfo"
    }
}

#endif
