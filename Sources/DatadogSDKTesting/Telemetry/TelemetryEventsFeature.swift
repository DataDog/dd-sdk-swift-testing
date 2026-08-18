/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

final class TelemetryEventsFeature: TestHooksFeature {
    static var id: FeatureId = "Telemetry Events"

    private let telemetry: Telemetry

    init(telemetry: Telemetry) {
        self.telemetry = telemetry
    }

    // MARK: - Session

    func testSessionWillStart(session: any TestSession) {
        telemetry.metrics.session.started.add(
            provider: session.configuration.env.ci?.provider, autoInjected: false)
        telemetry.metrics.events.created.add(
            testFramework: session.testFrameworks.telemetryTag, eventType: .session)
        session.emitGitShaCheck(to: telemetry)
    }

    func testSessionWillEnd(session: any TestSession) {
        telemetry.metrics.events.finished.add(
            testFramework: session.testFrameworks.telemetryTag, eventType: .session)
    }

    // MARK: - Module

    func testModuleWillStart(module: any TestModule) {
        telemetry.metrics.events.created.add(
            testFramework: module.testFrameworks.telemetryTag, eventType: .module)
    }

    func testModuleWillEnd(module: any TestModule) {
        telemetry.metrics.events.finished.add(
            testFramework: module.testFrameworks.telemetryTag, eventType: .module)
    }

    // MARK: - Suite

    func testSuiteWillStart(suite: any TestSuite, testsCount: UInt) {
        telemetry.metrics.events.created.add(testFramework: suite.testFramework.name, eventType: .suite)
    }

    func testSuiteWillEnd(suite: any TestSuite) {
        telemetry.metrics.events.finished.add(testFramework: suite.testFramework.name, eventType: .suite)
    }

    // MARK: - Test

    func testWillStart(test: any TestRun, info: TestRunInfoStart) {
        telemetry.metrics.events.created.add(testFramework: test.suite.testFramework.name,
                                              eventType: .test)
    }

    func testWillFinish(test: any TestRun, duration: TimeInterval, withStatus status: TestStatus,
                        andInfo info: TestRunInfoEnd)
    {
        let attrs = test.attributes
        let isNew: Bool?       = attrs[DDTestTags.testIsNew]?.asString == "true" ? true : nil
        let isRetry: Bool?     = attrs[DDEfdTags.testIsRetry]?.asString == "true" ? true : nil
        let retryReason        = telemetryRetryReason(from: attrs[DDEfdTags.testRetryReason]?.asString)
        let isBenchmark: Bool? = attrs[DDTestTags.testType]?.asString == DDTagValues.typeBenchmark ? true : nil
        let efdAbort           = telemetryEFDAbortReason(from: attrs[DDEfdTags.testEfdAbortReason]?.asString)

        telemetry.metrics.events.finished.add(testFramework: test.suite.testFramework.name,
                                               eventType: .test,
                                               isBenchmark: isBenchmark,
                                               earlyFlakeDetectionAbortReason: efdAbort,
                                               isNew: isNew, isRetry: isRetry,
                                               retryReason: retryReason)
    }

    func stop() {}

    private func telemetryRetryReason(from string: String?) -> Telemetry.RetryReason? {
        switch string {
        case DDTagValues.retryReasonEarlyFlakeDetection: return .earlyFlakeDetection
        case DDTagValues.retryReasonAutoTestRetry: return .autoTestRetry
        default: return nil
        }
    }

    private func telemetryEFDAbortReason(from string: String?) -> Telemetry.EFDAbortReason? {
        guard string == DDTagValues.efdAbortSlow else { return nil }
        return .slow
    }
}

// MARK: - Framework telemetry tag

private extension Set<String> {
    /// Metric tags carry a single opaque value per dimension (never parsed as JSON), so a
    /// mix of frameworks is safely reported as a stable "name1+name2" combination instead of
    /// a generic label — that keeps sessions using several frameworks distinguishable in metrics.
    var telemetryTag: String {
        switch count {
        case 0: return "Swift"
        case 1: return first!
        default: return sorted().joined(separator: "+")
        }
    }
}

// MARK: - TestSession telemetry helpers

extension TestSession {
    /// Emits `git.commit_sha_match` and one `git.commit_sha_discrepancy` per
    /// discrepancy found while assembling the session's git information.
    func emitGitShaCheck(to telemetry: Telemetry) {
        let git = configuration.env.git
        telemetry.metrics.git.commitShaMatch.add(matched: git.shaMatched)
        for d in git.discrepancies {
            telemetry.metrics.git.commitShaDiscrepancy.add(
                expectedProvider: d.expectedProvider,
                discrepantProvider: d.discrepantProvider,
                type: d.type)
        }
    }
}
