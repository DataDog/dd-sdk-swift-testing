/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import DatadogSDKTesting
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest

class CISpec: XCTestCase {
    var testObserver: DDTestObserver!
    var testEnvironment = [String: String]()
    var previousEnvironment = [String: String]()

    private func setEnvVariables() {
        DDEnvironmentValues.environment = testEnvironment
        DDEnvironmentValues.environment["DD_DONT_EXPORT"] = "true"
        testEnvironment = [String: String]()
    }

    override func setUp() {
        testEnvironment = [String: String]()
        previousEnvironment = DDEnvironmentValues.environment
    }

    override func tearDown() {
        XCTestObservationCenter.shared.removeTestObserver(testObserver)
        testObserver = nil
        DDEnvironmentValues.environment = previousEnvironment
    }

    func testGenerateSpecJson() throws {
        testEnvironment["DYLD_LIBRARY_PATH"] = ProcessInfo.processInfo.environment["DYLD_LIBRARY_PATH"]
        testEnvironment["DATADOG_CLIENT_TOKEN"] = "fakeToken"
        testEnvironment["CI_PIPELINE_URL"] = "https://foo/repo/-/pipelines/1234"
        testEnvironment["HOME"] = "/not-my-home"
        testEnvironment["USERPROFILE"] = "/not-my-home"
        testEnvironment["CI_PROJECT_DIR"] = "~/foo/bar"
        testEnvironment["CI_REPOSITORY_URL"] = "sample"
        testEnvironment["CI_COMMIT_BRANCH"] = "origin/master"
        testEnvironment["CI_COMMIT_TAG"] = "tag"
        testEnvironment["GITLAB_CI"] = "gitlab"
        testEnvironment["CI_PIPELINE_ID"] = "gitlab-pipeline-id"
        testEnvironment["CI_PROJECT_PATH"] = "gitlab-pipeline-name"
        testEnvironment["CI_PIPELINE_IID"] = "gitlab-pipeline-number"
        testEnvironment["CI_JOB_URL"] = "gitlab-job-url"
        testEnvironment["CI_JOB_NAME"] = "gitlab-job-name"
        testEnvironment["CI_JOB_STAGE"] = "gitlab-stage-name"
        testEnvironment["CI_COMMIT_SHA"] = "gitlab-git-commit"
        setEnvVariables()

        testObserver = DDTestObserver(tracer: DDTracer())
        testObserver.startObserving()
        testObserver.testBundleWillStart(Bundle(for: CISpec.self))

        testObserver.testCaseWillStart(self)

        measure {
            _ = 2 + 2
        }
        let span = OpenTelemetry.instance.contextProvider.activeSpan as! RecordEventsReadableSpan
        testObserver.testCaseDidFinish(self)

        let spanData = span.toSpanData()

        let keys = spanData.attributes.map { $0.key }.sorted()
        let keyJson = try JSONEncoder().encode(keys)
        if let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
            let fileManager = FileManager.default
            let fileURL = URL(fileURLWithPath: srcRoot).appendingPathComponent("ci-app-spec.json")
            try? fileManager.removeItem(at: fileURL)
            try keyJson.write(to: fileURL, options: .atomic)
        }
    }
}
