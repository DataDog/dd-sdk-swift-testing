/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter
internal import OpenTelemetryApi

/// Standalone `TestHooksFeature` that drives per-test code coverage
/// gathering and emits the related session/module/test tags. Coverage
/// used to live inside `TestImpactAnalysis`, but it has its own enable
/// gate (`DD_CIVISIBILITY_CODE_COVERAGE_ENABLED` plus the backend's
/// `code_coverage` setting) and must work even when TIA is off.
final class CodeCoverage: TestHooksFeature {
    static var id: FeatureId = "Code Coverage"

    let swiftTestingEnabled: Bool

    var isEnabled: Bool { _state.use { $0.collector != nil } }

    /// Single-slot state for the coverage collector and the currently-
    /// running session. LLVM gathering is a process-global flag, so only
    /// one session may be active at a time. If `testWillStart` ever fires
    /// while one is still in flight we end the prior session, log the
    /// conflict, and nil out `collector` — once cleared it can't be
    /// re-enabled for the rest of this run.
    private struct State {
        var collector: TestCoverageCollector?
        var active: ActiveCoverage?
    }
    private let _state: Synced<State>

    init(collector: TestCoverageCollector, swiftTestingEnabled: Bool) {
        self.swiftTestingEnabled = swiftTestingEnabled
        self._state = .init(.init(collector: collector, active: nil))
    }

    func testSessionWillEnd(session: any TestSession) {
        session.set(tag: DDTestSessionTags.testCodeCoverageEnabled, value: isEnabled)
        if session.get(metric: DDTestSessionTags.testCoverageLines) == nil,
           let linesCovered = CodeCoverageProvider.getLineCodeCoverage()
        {
            session.set(metric: DDTestSessionTags.testCoverageLines, value: linesCovered)
        }
    }

    func testModuleWillEnd(module: any TestModule) {
        module.set(tag: DDTestSessionTags.testCodeCoverageEnabled, value: isEnabled)
        // Coverage lines: set on both module and session (XCTest hack).
        if module.get(metric: DDTestSessionTags.testCoverageLines) == nil,
           let linesCovered = CodeCoverageProvider.getLineCodeCoverage()
        {
            module.set(metric: DDTestSessionTags.testCoverageLines, value: linesCovered)
            module.session.set(metric: DDTestSessionTags.testCoverageLines, value: linesCovered)
        }
    }

    func testWillStart(test: any TestRun, info: TestRunInfoStart) {
        guard !test.suite.isSwiftTesting || swiftTestingEnabled else { return }
        guard !info.skip.status.isSkipped else { return }

        let context = CoverageContext.test(testSpanId: test.id,
                                           suiteId: test.suite.id,
                                           sessionId: test.session.id)
        _state.update { state in
            guard let collector = state.collector else { return }
            if let prior = state.active {
                Log.print("""
                    Code coverage error: a coverage gathering session is already \
                    active for \(prior.context). Disabling code coverage for the \
                    rest of this run.
                    """)
                // Stop LLVM gathering for the prior session so the
                // collector goes back to a clean idle state, then drop
                // the collector — coverage stays off for this run.
                prior.end()
                state.active = nil
                state.collector = nil
                return
            }
            state.active = collector.startCoverage(context: context)
        }
    }

    func testDidFinish(test: any TestRun, info: TestRunInfoEnd) {
        guard !test.suite.isSwiftTesting || swiftTestingEnabled else { return }
        guard !info.skip.status.isSkipped else { return }

        let active: ActiveCoverage? = _state.update { state in
            let was = state.active
            state.active = nil
            return was
        }
        active?.end()
    }

    func stop() {
        _state.use { $0.collector }?.stop()
    }
}

struct CodeCoverageFactory: FeatureFactory {
    typealias FT = CodeCoverage

    let workspacePath: String?
    let priority: CodeCoveragePriority
    let tempFolder: Directory
    let debug: Bool
    let exporter: EventsExporterProtocol
    let swiftTestingEnabled: Bool

    static func isEnabled(config: Config, env: Environment, remote: TracerSettings) -> Bool {
        config.codeCoverageEnabled && remote.itr.codeCoverage
    }

    func create(log: Logger) -> CodeCoverage? {
        guard let provider = CodeCoverageProvider(storagePath: tempFolder,
                                                  exporter: exporter,
                                                  workspacePath: workspacePath,
                                                  priority: priority,
                                                  debug: debug)
        else {
            log.print("Code Coverage init failed.")
            return nil
        }
        log.debug("Code Coverage Enabled")
        return CodeCoverage(collector: provider, swiftTestingEnabled: swiftTestingEnabled)
    }
}
