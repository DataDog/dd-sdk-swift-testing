/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

#if canImport(Testing)
import Testing

public struct DatadogSwiftTestingTrait: TestTrait, SuiteTrait {
    public typealias TestScopeProvider = DatadogSwiftTestingScopeProvider
    
    public let isRecursive: Bool = true
    private let _provider: (any SwiftTestingSuiteProviderType)?
    
    init(provider: (any SwiftTestingSuiteProviderType)? = nil) {
        self._provider = provider
    }
    
    public func prepare(for test: Testing.Test) async throws {
        try await prepare(test: DatadogSwiftTestingScopeProvider.SwiftTest(test: test))
    }
    
    public func scopeProvider(for test: Testing.Test, testCase: Testing.Test.Case?) -> TestScopeProvider? {
        guard let provider = _activeProvider else {
            return nil
        }
        return TestScopeProvider(provider: provider)
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
    
    init(provider: any SwiftTestingSuiteProviderType) {
        self._provider = provider
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
        try await Self.datadogTest?.withGroup { group in
            nonisolated(unsafe) var shouldRetry: Bool = true
            while shouldRetry {
                let issues: Synced<DatadogSwiftTestingTrait.TestIssues> = .init(.init())
                
                let retry = await group.with(run: run) { run in
                    if let reason = run.group.configuration.skipReason {
                        return .skipped(reason: reason)
                    }
                    // Normal logic
                    nonisolated(unsafe) var isFailed: Bool = false
                    
                    do {
                        try await withKnownIssue(isIntermittent: true) {
                            try await function()
                        } matching: { issue in
                            if run.shouldSuppressError {
                                issues.update { $0.issues.append(issue) }
                                return true
                            }
                            isFailed = true
                            return false
                        }
                    } catch {
                        issues.update { $0.error = error }
                    }
                    
                    return issues.value.isFailed || isFailed ? .failed : .passed
                }
                switch retry {
                case .skipped(reason: _):
                    // Add Test.cancel for Xcode 26.4
                    shouldRetry = false
                case .retry(.end(let errors)):
                    shouldRetry = false
                    if !errors.ignore {
                        try issues.value.throwIfNeeded()
                    }
                case .retry(.retry(_, let errors)):
                    shouldRetry = true
                    if !errors.ignore {
                        try issues.value.throwIfNeeded()
                    }
                }
            }
        }
    }
    
    @TaskLocal static var datadogSuite: SwiftTestingSuiteContext? = nil
    @TaskLocal static var datadogTest: SwiftTestingTestContext? = nil
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
        
//        var parameters: [(name: String, value: String)] {
//            guard isParametrised else { return [] }
//            let description = String(describing: testCase)
//            return Self.parametersRegex.matches(
//                in: description, range: NSRange(description.startIndex..., in: description)
//            ).map { (String(description[Range($0.range(at: 1), in: description)!]),
//                     String(description[Range($0.range(at: 2), in: description)!])) }
//        }
//        
//        static let parametersRegex = try! NSRegularExpression(
//            pattern: #"\(arguments:\w\[\w+)"#,
//            options: []
//        )
    }
}

extension DatadogSwiftTestingTrait {
    public struct TestIssue: Error, Sendable {
        public let kind: Issue.Kind
        public let comments: [Comment]
        public let error: (any Error)?
        public let sourceLocation: SourceLocation?
        
        public init(issue: Testing.Issue) {
            self.kind = issue.kind
            self.comments = issue.comments
            self.error = issue.error
            self.sourceLocation = issue.sourceLocation
        }
    }
    
    public struct TestIssues: Error, Sendable {
        public fileprivate(set) var issues: [Testing.Issue] = []
        public fileprivate(set) var error: (any Error)? = nil
        
        public var isFailed: Bool { !issues.isEmpty || error != nil }
        
        fileprivate func throwIfNeeded() throws {
            if isFailed {
                if let error, issues.isEmpty {
                    throw error
                }
                if issues.count == 1 {
                    throw TestIssue(issue: issues.first!)
                }
                if issues.count > 1 {
                    throw self
                }
            }
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
#endif
