/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

@testable import DatadogSDKTesting
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest

class CISpec: XCTestCase {
    var testEnvironment = [String: String]()
    var previousEnvironment = [String: String]()

    private func setEnvVariables() {
        DDEnvironmentValues.environment = testEnvironment
        DDEnvironmentValues.environment["DD_DONT_EXPORT"] = "true"
        DDEnvironmentValues.environment["DD_DISABLE_TEST_INSTRUMENTING"] = "1"
        testEnvironment = [String: String]()
        DDTestMonitor.env = DDEnvironmentValues()
    }

    override func setUp() {
        XCTAssertNil(DDTracer.activeSpan)
        testEnvironment = [String: String]()
        previousEnvironment = DDEnvironmentValues.environment
    }

    override func tearDown() {
        XCTAssertNil(DDTracer.activeSpan)
        DDEnvironmentValues.environment = previousEnvironment
    }

    func testGenerateSpecJson() throws {
        testEnvironment["DYLD_LIBRARY_PATH"] = ProcessInfo.processInfo.environment["DYLD_LIBRARY_PATH"]
        testEnvironment["SRCROOT"] = ProcessInfo.processInfo.environment["SRCROOT"]
        testEnvironment["DATADOG_CLIENT_TOKEN"] = "fakeToken"
        testEnvironment["CI_PIPELINE_URL"] = "https://foo/repo/-/pipelines/1234"
        testEnvironment["HOME"] = "/not-my-home"
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
        setEnvVariables()

        let testSession = DDTestSession.start(bundleName: Bundle(for: CISpec.self).bundleURL.deletingPathExtension().lastPathComponent)
        let suite = testSession.suiteStart(name: "CISpec")
        let test = suite.testStart(name: "testGenerateSpecJson")
        test.addBenchmark(name: "duration", samples: [1, 2, 3, 4, 5], info: "")
        let span = OpenTelemetry.instance.contextProvider.activeSpan as! RecordEventsReadableSpan
        test.end(status: .pass)

        let spanData = span.toSpanData()

        let keys = spanData.attributes.map { $0.key }
            .filter { $0 != "type" && $0 != "resource.name" }
            .sorted()
        let keyJson = try JSONEncoder().encode(keys)
        if let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
            let fileManager = FileManager.default
            let fileURL = URL(fileURLWithPath: srcRoot).appendingPathComponent("ci-app-spec.json")
            try? fileManager.removeItem(at: fileURL)
            try keyJson.write(to: fileURL, options: .atomic)
        }
    }
}
