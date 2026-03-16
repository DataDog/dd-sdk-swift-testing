//
//  SwiftTestingObserver.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 12/03/2026.
//
import Testing
import Foundation

public struct DatadogSwiftTestingScopingTrait: TestTrait, SuiteTrait, TestScoping {
    public let isRecursive: Bool
    private let _observer: (any SwiftTestingObserverType)?
    
    public init() {
        self.init(observer: Self.sharedObserver)
    }
    
    init(observer: (any SwiftTestingObserverType)?) {
        self.isRecursive = true
        self._observer = observer
    }
    
    public func provideScope(for test: Testing.Test, testCase: Testing.Test.Case?,
                             performing function: @Sendable () async throws -> Void) async throws
    {
        // It's a suite. Ignore it, we interested only in tests here
        guard let testCase else {
            return try await function()
        }
        // Pass it to our method. Useful for mocks
        try await provideScope(testRun: SwiftTestingObserver.SwiftTestRun(test: test, testCase: testCase),
                               performing: function)
    }
    
    public func prepare(for test: Testing.Test) async throws {
        try await prepare(test: test)
    }
    
    func prepare(test: some SwiftTestingTest) async throws {
        try await _observer?.register(test: test)
    }
    
    
    func provideScope(testRun: some SwiftTestingTestRun, performing function: @Sendable () async throws -> Void) async throws {
        // We don't observe in this session
        guard let observer = _observer else {
            return try await function()
        }
        
        nonisolated(unsafe) var shouldRetry: Bool = true
        while shouldRetry {
            // Skip test
            if let reason = try await observer.willRun(testRun: testRun).skipReason {
                // Add Test.cancel for Xcode 26.4
                shouldRetry = try await observer.didRun(testRun: testRun, status: .skipped(reason: reason)).isRetry
                continue
            }
            // Normal logic
            let issues: Synced<TestExecutionFailedError> = .init(.init(issues: []))
            nonisolated(unsafe) var isFailed: Bool = false
            
            do {
                try await withKnownIssue(isIntermittent: true) {
                    try await function()
                } matching: { issue in
                    if observer.shouldSuppressError(testRun: testRun) {
                        issues.update { $0.issues.append(issue) }
                        return true
                    }
                    isFailed = true
                    return false
                }
            } catch {
                issues.update { $0.error = error }
            }
            
            let status: SwiftTestingTestStatus = issues.value.isFailed || isFailed ? .failed : .passed
            switch try await observer.didRun(testRun: testRun, status: status) {
            case .end(let errors):
                shouldRetry = false
                if !errors.ignore {
                    try issues.value.throwIfNeeded()
                }
            case .retry(_, let errors):
                shouldRetry = true
                if !errors.ignore {
                    try issues.value.throwIfNeeded()
                }
            }
        }
    }
    
    static var sharedObserver: (any SwiftTestingObserverType)? = nil
}


extension Testing.Trait where Self == DatadogSwiftTestingScopingTrait {
    public static var datadogTesting: Self { Self() }
}

extension Testing.Test: SwiftTestingTest {
    var module: String { id.moduleName }
    
    var suite: String {
        guard !isSuite else { return name }
        let components = id.nameComponents
        if components.count > 1 || components.first?.last != ")" {
            return components.first!
        } else {
            return "[\(sourceLocation.fileName.replacingOccurrences(of: ".swift", with: ""))]"
        }
    }
}

extension SwiftTestingObserver {
    struct SwiftTestRun: SwiftTestingTestRun {
        let test: Testing.Test
        let testCase: Testing.Test.Case
        
        var name: String { test.name }
        var module: String { test.module }
        var isSuite: Bool { test.isSuite }
        var suite: String { test.suite }
        
        var isParametrised: Bool { testCase.isParameterized }
    }
}

public struct TestExecutionFailedError: Error, Sendable {
    fileprivate(set) var issues: [Testing.Issue]
    fileprivate(set) var error: (any Error)?
    
    var isFailed: Bool { !issues.isEmpty || error != nil }
}

private extension TestExecutionFailedError {
    func throwIfNeeded() throws {
        if isFailed {
            if let error, issues.isEmpty {
                throw error
            }
            throw self
        }
    }
}
