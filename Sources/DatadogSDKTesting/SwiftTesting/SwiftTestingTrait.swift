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
         actions: any DatadogSwiftTestingTestActions = DatadogSwiftTestingScopeProvider.Actions())
    {
        self._provider = provider
        self._actions = actions
    }
    
    public func prepare(for test: Testing.Test) async throws {
        try await prepare(test: DatadogSwiftTestingScopeProvider.SwiftTest(test: test))
    }
    
    public func scopeProvider(for test: Testing.Test, testCase: Testing.Test.Case?) -> TestScopeProvider? {
        guard let provider = _activeProvider else {
            return nil
        }
        return TestScopeProvider(provider: provider, actions: _actions)
    }
    
    func prepare(test: some SwiftTestingTestInfoType) async throws {
        try await _activeProvider?.registry.register(test: test)
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
            guard isParameterized else { return .init(arguments: .nil, metadata: nil) }
            let parameters = Self.parseSwiftTestCaseParameters(from: String(describing: testCase))
            let args: [JSONGeneric] = parameters.map {
                .object(["name": .string($0.name), "value": .string($0.value), "type": .string($0.type)])
            }
            return .init(arguments: .array(args), metadata: nil)
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
}

extension Testing.Test {
    var ddModule: String { id.moduleName }
    
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
        guard !isSuite else { return name }
        if ddHasSuite {
            return id.nameComponents.first!
        } else {
            return "[\(sourceLocation.fileName.replacingOccurrences(of: ".swift", with: ""))]"
        }
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

extension DatadogSwiftTestingScopeProvider.SwiftTestRun {
    // Parses a Testing.Test.Case description string into (name, value, type) triples.
    // name = firstName joined with secondName (when present) using a space.
    // Exposed as `internal` so unit tests can exercise it directly without
    // requiring the Swift Testing runtime.
    static func parseSwiftTestCaseParameters(from description: String) -> [(name: String, value: String, type: String)] {
        _swiftTestCaseParametersRegex
            .matches(in: description, range: NSRange(description.startIndex..., in: description))
            .compactMap { match in
                guard let valueRange     = Range(match.range(at: 1), in: description),
                      let firstNameRange = Range(match.range(at: 2), in: description) else {
                    return nil
                }
                var name = String(description[firstNameRange])
                if let secondNameRange = Range(match.range(at: 3), in: description) {
                    name += " " + description[secondNameRange]
                }
                let type: String
                if let typeRange = Range(match.range(at: 4), in: description) {
                    type = String(description[typeRange])
                } else {
                    type = "<unknown>"
                }
                return (name: name, value: String(description[valueRange]), type: type)
            }
    }

    // Matches each Testing.Test.Case.Argument, capturing:
    //   group 1 — argument value (up to ", id: Testing.Test.Case.Argument.ID")
    //   group 2 — parameter firstName
    //   group 3 — parameter secondName (absent when secondName is nil);
    //             handles `Optional("name")` form only (nil = absent)
    //   group 4 — parameter typeInfo (absent when not present)
    private static let _swiftTestCaseParametersRegex = try! NSRegularExpression(
        pattern: #"Argument\(value: (.*?), id: (?:.*?), parameter: \S*Parameter\(index: \d+, firstName: "([^"]*)", secondName: (?:nil|Optional\("([^"]*)"\))[^)]*?(?:, typeInfo: ([^)]+))?\)"#,
        options: []
    )
}

#endif
