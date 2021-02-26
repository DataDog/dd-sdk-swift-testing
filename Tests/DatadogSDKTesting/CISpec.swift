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

    private func setEnvVariables() {
        DDEnvironmentValues.environment = testEnvironment
        testEnvironment = [String: String]()
    }

    override func tearDown() {
        XCTestObservationCenter.shared.removeTestObserver(testObserver)
        testObserver = nil
    }

    func testGenerateSpecJson() throws {
        testEnvironment["DATADOG_CLIENT_TOKEN"] = "fakeToken"
        testEnvironment["JENKINS_URL"] = "http://jenkins.com/"
        testEnvironment["GIT_URL"] = "/test/repo"
        testEnvironment["GIT_COMMIT"] = "37e376448b0ac9b7f54404"
        testEnvironment["WORKSPACE"] = "/build"
        testEnvironment["BUILD_TAG"] = "pipeline1"
        testEnvironment["BUILD_NUMBER"] = "45"
        testEnvironment["BUILD_URL"] = "http://jenkins.com/build"
        testEnvironment["GIT_BRANCH"] = "/origin/develop"
        testEnvironment["JOB_NAME"] = "job1"
        setEnvVariables()

        testObserver = DDTestObserver(tracer: DDTracer())
        testObserver.startObserving()

        
        testObserver.testCaseWillStart(self)

        
        measure {
            let _ = 2+2
        }
        let span = testObserver.tracer.tracerSdk.activeSpan as! RecordEventsReadableSpan
        testObserver.testCaseDidFinish(self)

        let spanData = span.toSpanData()

        let keys = spanData.attributes.map { $0.key }.sorted()
        let keyJson = try JSONEncoder().encode(keys)
        if let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
            try keyJson.write(to: URL(fileURLWithPath: srcRoot).appendingPathComponent("ci-app-spec.json"), options: .atomic)
        }

    }
}
