/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

/// Tracks communication errors that occurred while fetching library
/// configuration data from the backend (settings, skippable tests, flaky tests,
/// known tests, test management tests). Each flag is sticky: once set to
/// `true` it stays `true` until the tracker is discarded.
final class LibraryConfigurationErrors: @unchecked Sendable {
    enum Kind: Hashable, CaseIterable {
        case settings
        case skippableTests
        case flakyTests
        case knownTests
        case testManagementTests
    }

    private let lock = NSLock()
    private var flags: Set<Kind> = []

    subscript(_ kind: Kind) -> Bool {
        lock.withLock { flags.contains(kind) }
    }

    /// Marks the request kind as having failed with a communication error.
    func recordCommunicationError(_ kind: Kind) {
        lock.withLock { _ = flags.insert(kind) }
    }
}

final class AdditionalTags: TestHooksFeature {
    static let id: FeatureId = "Additional Test Tags"

    let codeCoverage: Bool
    let bundleFunctions: FunctionMap
    let codeOwners: CodeOwners?
    let workspacePath: String?
    
    struct SuiteOwners {
        private var _owners: [String: Int] = [:]
        
        var owners: [String] {
            _owners.sorted { $0.value < $1.value }.map { $0.key }
        }
        
        var isEmpty: Bool { _owners.isEmpty }
        
        mutating func add(owners: [String]) {
            for owner in owners where _owners[owner] == nil {
                _owners[owner] = _owners.count
            }
        }
    }

    private let suiteOwners: Synced<[ObjectIdentifier: SuiteOwners]>

    init(codeCoverage: Bool = false, bundleFunctions: FunctionMap = [:], codeOwners: CodeOwners? = nil, workspacePath: String? = nil) {
        self.codeCoverage = codeCoverage
        self.bundleFunctions = bundleFunctions
        self.codeOwners = codeOwners
        self.workspacePath = workspacePath
        self.suiteOwners = .init([:])
    }

    func testSessionWillEnd(session: any TestSession) {
        // Coverage lines when TIA is not active (TIA handles this in its hook otherwise)
        if codeCoverage, session.metrics[DDTestSessionTags.testCoverageLines] == nil,
           let linesCovered = DDCoverageHelper.getLineCodeCoverage()
        {
            session.set(metric: DDTestSessionTags.testCoverageLines, value: linesCovered)
        }
    }

    func testModuleWillEnd(module: any TestModule) {
        // Coverage lines when TIA is not active (TIA handles this in its hook otherwise)
        if codeCoverage, module.metrics[DDTestSessionTags.testCoverageLines] == nil,
           let linesCovered = DDCoverageHelper.getLineCodeCoverage()
        {
            module.set(metric: DDTestSessionTags.testCoverageLines, value: linesCovered)
            module.session.set(metric: DDTestSessionTags.testCoverageLines, value: linesCovered)
        }
    }

    func testSuiteWillEnd(suite: any TestSuite) {
        let owners = suiteOwners.update { $0.removeValue(forKey: ObjectIdentifier(suite)) }
        if let owners, !owners.isEmpty {
            suite.set(tag: DDTestTags.testCodeowners, value: CodeOwners.format(owners.owners))
        }
    }

    func testWillStart(test: any TestRun, info: TestRunInfoStart) {
        if let functionInfo = bundleFunctions["\(test.suite.name).\(test.name)"] {
            let filePath = stripWorkspace(from: functionInfo.file)
            test.set(tag: DDTestTags.testSourceFile, value: filePath)
            test.set(tag: DDTestTags.testSourceStartLine, value: functionInfo.startLine)
            test.set(tag: DDTestTags.testSourceEndLine, value: functionInfo.endLine)
            if let owners = codeOwners?.owners(forPath: filePath) {
                test.set(tag: DDTestTags.testCodeowners, value: CodeOwners.format(owners))
                suiteOwners.update { state in
                    state[ObjectIdentifier(test.suite), default: .init()].add(owners: owners)
                }
            }
        }
        if let retry = info.retry {
            test.set(tag: DDEfdTags.testIsRetry, value: "true")
            test.set(tag: DDEfdTags.testRetryReason, value: retry.reason)
        }
    }

    func testWillFinish(test: any TestRun, duration: TimeInterval,
                        withStatus status: TestStatus, andInfo info: TestRunInfoEnd)
    {
        if status == .skip, let skip = info.skip.by {
            test.set(tag: DDTestTags.testSkipReason, value: skip.reason)
        }
        if info.executions.total > 0 && !info.retry.status.isRetry {
            // This was a retry and retries are finished
            if info.executions.failed >= info.executions.total && status == .fail {
                // last execution and all previous executions failed
                test.set(tag: DDTestTags.testHasFailedAllRetries, value: "true")
            }
        }
        if status == .fail, case .suppressed(reason: let reason) = info.retry.status.errorsStatus {
            test.set(tag: DDTestTags.testFailureSuppressionReason, value: reason)
        }
        if !info.retry.status.isRetry,
           (info.retry.feature ?? .notFeature) == .notFeature,
           (info.skip.by?.feature ?? .notFeature) == .notFeature
        {
            // This is the last run and test wasn't handled by any features (skip or retry)
            test.set(tag: DDTestTags.testFinalStatus,
                     value: status.final(ignoreErrors: info.retry.status.ignoreErrors))
        }
    }

    func stop() {}
    
    private func stripWorkspace(from path: String) -> String {
        guard let workspacePath,
              let range = path.range(of: workspacePath + "/")
        else { return path }
        var result = path
        result.removeSubrange(range)
        return result
    }
}

/// Adds `_dd.ci.library_configuration_error.*` hidden tags to every test,
/// suite, module and session event whenever a backend communication error
/// occurred while fetching library configuration data.
final class LibraryConfigurationErrorTags: TestHooksFeature {
    static let id: FeatureId = "Library Configuration Error Tags"

    let errors: LibraryConfigurationErrors

    init(errors: LibraryConfigurationErrors) {
        self.errors = errors
    }

    private static let tagByKind: [LibraryConfigurationErrors.Kind: String] = [
        .settings: DDLibraryConfigurationErrorTags.settings,
        .skippableTests: DDLibraryConfigurationErrorTags.skippableTests,
        .flakyTests: DDLibraryConfigurationErrorTags.flakyTests,
        .knownTests: DDLibraryConfigurationErrorTags.knownTests,
        .testManagementTests: DDLibraryConfigurationErrorTags.testManagementTests
    ]

    private func apply(_ setter: (String, String) -> Void) {
        for (kind, tag) in Self.tagByKind where errors[kind] {
            setter(tag, "true")
        }
    }

    func testSessionWillEnd(session: any TestSession) {
        apply { session.set(tag: $0, value: $1) }
    }

    func testModuleWillEnd(module: any TestModule) {
        apply { module.set(tag: $0, value: $1) }
    }

    func testSuiteWillEnd(suite: any TestSuite) {
        apply { suite.set(tag: $0, value: $1) }
    }

    func testWillStart(test: any TestRun, info: TestRunInfoStart) {
        apply { test.set(tag: $0, value: $1) }
    }

    func stop() {}
}
