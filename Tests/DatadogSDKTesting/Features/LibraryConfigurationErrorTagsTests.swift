/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting

// MARK: - Tracker

final class LibraryConfigurationErrorsTrackerTests: XCTestCase {
    func testFlagsAreFalseByDefault() {
        let tracker = LibraryConfigurationErrors()
        for kind in LibraryConfigurationErrors.Kind.allCases {
            XCTAssertFalse(tracker[kind], "expected \(kind) to be false by default")
        }
    }

    func testRecordCommunicationErrorIsSticky() {
        let tracker = LibraryConfigurationErrors()
        tracker.recordCommunicationError(.settings)
        XCTAssertTrue(tracker[.settings])

        // Recording again keeps it true (no toggle).
        tracker.recordCommunicationError(.settings)
        XCTAssertTrue(tracker[.settings])
    }

    func testKindsAreIndependent() {
        let tracker = LibraryConfigurationErrors()
        tracker.recordCommunicationError(.knownTests)
        tracker.recordCommunicationError(.testManagementTests)

        XCTAssertTrue(tracker[.knownTests])
        XCTAssertTrue(tracker[.testManagementTests])
        XCTAssertFalse(tracker[.settings])
        XCTAssertFalse(tracker[.skippableTests])
        XCTAssertFalse(tracker[.flakyTests])
    }
}

// MARK: - Feature

final class LibraryConfigurationErrorTagsFeatureTests: XCTestCase {
    private let module = "MyModule"
    private let suite = "MySuite"
    private let test = "testThing"

    func testAppliesNoTagsWhenNoErrorRecorded() async {
        let session = await runSession(with: LibraryConfigurationErrors())

        for tag in allErrorTags() {
            XCTAssertNil(session.tags[tag], "session should not carry \(tag)")
            XCTAssertNil(session[module]?.tags[tag], "module should not carry \(tag)")
            XCTAssertNil(session[module]?[suite]?.tags[tag], "suite should not carry \(tag)")
            XCTAssertNil(session[module]?[suite]?[test]?[0]?.tags[tag],
                         "test should not carry \(tag)")
        }
    }

    func testRecordedKindIsTaggedOnEveryEvent() async {
        let cases: [(LibraryConfigurationErrors.Kind, String)] = [
            (.settings, DDLibraryConfigurationErrorTags.settings),
            (.skippableTests, DDLibraryConfigurationErrorTags.skippableTests),
            (.flakyTests, DDLibraryConfigurationErrorTags.flakyTests),
            (.knownTests, DDLibraryConfigurationErrorTags.knownTests),
            (.testManagementTests, DDLibraryConfigurationErrorTags.testManagementTests)
        ]

        for (kind, tag) in cases {
            let tracker = LibraryConfigurationErrors()
            tracker.recordCommunicationError(kind)
            let session = await runSession(with: tracker)

            XCTAssertEqual(session.tags[tag], "true", "session missing \(tag) for \(kind)")
            XCTAssertEqual(session[module]?.tags[tag], "true",
                           "module missing \(tag) for \(kind)")
            XCTAssertEqual(session[module]?[suite]?.tags[tag], "true",
                           "suite missing \(tag) for \(kind)")
            XCTAssertEqual(session[module]?[suite]?[test]?[0]?.tags[tag], "true",
                           "test missing \(tag) for \(kind)")

            // Other kinds' tags must not leak in.
            for otherTag in allErrorTags() where otherTag != tag {
                XCTAssertNil(session.tags[otherTag],
                             "session should not carry \(otherTag) when only \(kind) is recorded")
                XCTAssertNil(session[module]?[suite]?[test]?[0]?.tags[otherTag],
                             "test should not carry \(otherTag) when only \(kind) is recorded")
            }
        }
    }

    func testMultipleRecordedKindsProduceMultipleTags() async {
        let tracker = LibraryConfigurationErrors()
        tracker.recordCommunicationError(.settings)
        tracker.recordCommunicationError(.knownTests)

        let session = await runSession(with: tracker)

        XCTAssertEqual(session.tags[DDLibraryConfigurationErrorTags.settings], "true")
        XCTAssertEqual(session.tags[DDLibraryConfigurationErrorTags.knownTests], "true")
        XCTAssertNil(session.tags[DDLibraryConfigurationErrorTags.skippableTests])
        XCTAssertNil(session.tags[DDLibraryConfigurationErrorTags.flakyTests])
        XCTAssertNil(session.tags[DDLibraryConfigurationErrorTags.testManagementTests])
    }

    // MARK: helpers

    private func runSession(with tracker: LibraryConfigurationErrors) async -> Mocks.Session {
        let feature: TestHooksFeature = LibraryConfigurationErrorTags(errors: tracker)
        let testsToRun: Mocks.Runner.Tests = [module: [
            suite: [test: .pass()]
        ]]
        return await Mocks.Runner(features: [feature], tests: testsToRun).run()
    }

    private func allErrorTags() -> [String] {
        [
            DDLibraryConfigurationErrorTags.settings,
            DDLibraryConfigurationErrorTags.skippableTests,
            DDLibraryConfigurationErrorTags.flakyTests,
            DDLibraryConfigurationErrorTags.knownTests,
            DDLibraryConfigurationErrorTags.testManagementTests
        ]
    }
}
