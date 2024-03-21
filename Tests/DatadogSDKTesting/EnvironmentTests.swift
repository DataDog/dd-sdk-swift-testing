/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest
import EventsExporter

struct FixtureError: Error, CustomStringConvertible {
    let description: String
}

class EnvironmentTests: XCTestCase {
    // list of attributes stored as json
    let jsonAttributes = ["_dd.ci.env_vars", "ci.node.labels"]

    var tracerProvider = TracerProviderSdk()
    var tracerSdk: Tracer!
    
    override func setUp() {
        XCTAssertNil(DDTracer.activeSpan)
        OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
        tracerSdk = tracerProvider.get(instrumentationName: "SpanBuilderSdkTest", instrumentationVersion: nil)
    }

    override func tearDown() {
        XCTAssertNil(DDTracer.activeSpan)
    }

    func testAddsTagsToSpan() {
        var testEnvironment = [String: SpanAttributeConvertible]()
        testEnvironment["JENKINS_URL"] = "http://jenkins.com/"
        testEnvironment["GIT_URL"] = "/test/repo"
        testEnvironment["GIT_COMMIT"] = "37e376448b0ac9b7f54404"
        testEnvironment["WORKSPACE"] = "/build"
        testEnvironment["BUILD_TAG"] = "pipeline1"
        testEnvironment["BUILD_NUMBER"] = "45"
        testEnvironment["BUILD_URL"] = "http://jenkins.com/build"
        testEnvironment["GIT_BRANCH"] = "/origin/develop"
        testEnvironment["JOB_NAME"] = "job1"

        let span = createSimpleSpan()
        let env = createEnv(testEnvironment)
        span.addTags(from: env)

        let spanData = span.toSpanData()

        XCTAssertEqual(spanData.attributes["ci.provider.name"]?.description, "jenkins")
        XCTAssertEqual(spanData.attributes["git.repository_url"]?.description, "/test/repo")
        XCTAssertEqual(spanData.attributes["git.commit.sha"]?.description, "37e376448b0ac9b7f54404")
        XCTAssertEqual(spanData.attributes["ci.workspace_path"]?.description, "/build")
        XCTAssertEqual(spanData.attributes["ci.pipeline.id"]?.description, "pipeline1")
        XCTAssertEqual(spanData.attributes["ci.pipeline.number"]?.description, "45")
        XCTAssertEqual(spanData.attributes["ci.pipeline.url"]?.description, "http://jenkins.com/build")
        XCTAssertEqual(spanData.attributes["ci.pipeline.name"]?.description, "job1")
        XCTAssertEqual(spanData.attributes["git.branch"]?.description, "develop")
    }

    func testWhenNotRunningInCI_CITagsAreNotAdded() {
        var testEnvironment = [String: SpanAttributeConvertible]()
        testEnvironment["SRCROOT"] = ProcessInfo.processInfo.environment["SRCROOT"]

        let span = createSimpleSpan()
        let env = createEnv(testEnvironment)
        span.addTags(from: env)

        let spanData = span.toSpanData()
        XCTAssertNotNil(spanData.attributes[DDCITags.ciWorkspacePath])
        XCTAssertNil(spanData.attributes[DDCITags.ciProvider])
    }

    func testAddCustomTagsWithDDTags() {
        var testEnvironment = [String: SpanAttributeConvertible]()
        testEnvironment["DD_TAGS"] = "key1:value1 key2:value2 key3:value3 keyFoo:$FOO keyFooFoo:$FOOFOO keyMix:$FOO-v1"
        testEnvironment["FOO"] = "BAR"
        testEnvironment["SRCROOT"] = ProcessInfo.processInfo.environment["SRCROOT"]

        let span = createSimpleSpan()
        let env = createEnv(testEnvironment)
        span.addTags(from: env)

        let spanData = span.toSpanData()
        XCTAssertEqual(spanData.attributes["key1"]?.description, "value1")
        XCTAssertEqual(spanData.attributes["key2"]?.description, "value2")
        XCTAssertEqual(spanData.attributes["key3"]?.description, "value3")
        XCTAssertEqual(spanData.attributes["keyFoo"]?.description, "BAR")
        XCTAssertEqual(spanData.attributes["keyFooFoo"]?.description, "$FOOFOO")
        XCTAssertEqual(spanData.attributes["keyMix"]?.description, "BAR-v1")
        XCTAssertNotNil(spanData.attributes[DDCITags.ciWorkspacePath])
    }

    private func createSimpleSpan() -> RecordEventsReadableSpan {
        return tracerSdk.spanBuilder(spanName: "spanName").startSpan() as! RecordEventsReadableSpan
    }

    func testRepositoryName() {
        var testEnvironment = [String: SpanAttributeConvertible]()
        testEnvironment["GITHUB_ACTION"] = "run"
        testEnvironment["GITHUB_REPOSITORY"] = "therepo"

        let env = createEnv(testEnvironment)

        XCTAssertEqual(env.git.repositoryURL?.description, "https://github.com/therepo.git")
        XCTAssertEqual(env.git.repositoryName, "therepo")
    }

    func testIfCommitHashFromEnvironmentIsNotSetGitFolderIsEvaluated() {
        var testEnvironment = [String: SpanAttributeConvertible]()
        testEnvironment["GITHUB_ACTION"] = "run"
        testEnvironment["GITHUB_SHA"] = nil
        testEnvironment["SRCROOT"] = ProcessInfo.processInfo.environment["SRCROOT"]

        let env = createEnv(testEnvironment)

        XCTAssertNotNil(env.git.commitMessage)
    }

    func testIfCommitHashFromEnvironmentIsSetAndDifferentFromGitFolderThenGitFolderIsNotEvaluated() {
        var testEnvironment = [String: SpanAttributeConvertible]()
        testEnvironment["GITHUB_ACTION"] = "run"
        testEnvironment["GITHUB_SHA"] = "environmentSHA"

        let env = createEnv(testEnvironment)

        XCTAssertNil(env.git.commitMessage)
        XCTAssertEqual(env.git.commitSHA, "environmentSHA")
    }

    func testIfCommitHashFromEnvironmentIsSetAndEqualsFromGitFolderThenGitFolderIsEvaluated() {
        let gitInfo = Environment.gitInfoAt(startingPath: #file)

        var testEnvironment = [String: SpanAttributeConvertible]()
        testEnvironment["GITHUB_WORKSPACE"] = "/tmp/folder"
        testEnvironment["GITHUB_SHA"] = gitInfo?.commit
        testEnvironment["SRCROOT"] = ProcessInfo.processInfo.environment["SRCROOT"]

        let env = createEnv(testEnvironment)

        XCTAssertNotNil(env.git.commitMessage)
        XCTAssertEqual(env.git.commitSHA, gitInfo?.commit)
    }

    func testGitInfoIsNilWhenNotGitFolderExists() {
        let gitInfo = Environment.gitInfoAt(startingPath: "/Users/")
        XCTAssertNil(gitInfo)
    }

    func testSpecs() throws {
        let fixturesURL = Bundle(for: type(of: self)).resourceURL!
            .appendingPathComponent("fixtures")
            .appendingPathComponent("ci")
        let fileEnumerator = FileManager.default.enumerator(at: fixturesURL, includingPropertiesForKeys: nil)!

        var numTestedFiles = 0
        for case let fileURL as URL in fileEnumerator {
            // check is json
            guard fileURL.pathExtension == "json" else { continue }
            
            let ciName = fileURL.lastPathComponent
                .replacingOccurrences(of: ".json", with: "")
            
            numTestedFiles += 1
            
            do {
                try validateSpec(file: fileURL, ci: ciName)
            } catch {
                print("[FixtureError] JSON serialization failed on file: \(fileURL)")
                let content = try String(contentsOf: fileURL)
                if content.isEmpty {
                    print("[FixtureError] File is empty" + content)
                } else {
                    print("[FixtureError] content:\n" + content)
                }
                throw error
            }
        }
        XCTAssertGreaterThan(numTestedFiles, 0)
    }
    
    private func createEnv(_ env: [String: SpanAttributeConvertible]) -> Environment {
        let reader = ProcessEnvironmentReader(environment: env.mapValues { $0.spanAttribute }, infoDictionary: [:])
        let config = Config(env: reader)
        return Environment(config: config, env: reader, log: Log.instance)
    }

    private func validateSpec(file: URL, ci: String) throws {
        print("validating \(ci)")
        let data = try Data(contentsOf: file)
        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [Any] else {
            throw FixtureError(description: "[FixtureError] JSON serialization failed on file: \(file)")
        }

        try json.forEach { specVal in
            guard let spec = specVal as? [[String: String]] else {
                throw FixtureError(description: "[FixtureError] spec invalid: \(specVal)")
            }
            
            let span = createSimpleSpan()
            let env = createEnv(spec[0])
            
            span.addTags(from: env)
            let spanData = span.toSpanData()

            spec[1].forEach {
                let data = spanData.attributes[$0.key]?.description
                if jsonAttributes.firstIndex(of: $0.key) != nil {
                    XCTAssertTrue(compareJsons(data, $0.value),
                                  "\(ci) > \($0.key): \(data ?? "nil") != \($0.value)")
                } else {
                    XCTAssertEqual(data, $0.value,
                                   "\(ci) > \($0.key): \(data ?? "nil") != \($0.value)")
                }
            }
        }
    }

    private func compareJsons(_ string1: String?, _ string2: String) -> Bool {
        guard let string1 = string1 else { return false }
        if let json1 = try? JSONSerialization.jsonObject(with: string1.utf8Data) as? [String: String],
           let json2 = try? JSONSerialization.jsonObject(with: string2.utf8Data) as? [String: String]
        {
            return json1 == json2
        } else if let json1 = try? JSONSerialization.jsonObject(with: string1.utf8Data) as? [String],
                  let json2 = try? JSONSerialization.jsonObject(with: string2.utf8Data) as? [String]
        {
            return json1.sorted() == json2.sorted()
        } else {
            return false
        }
    }
}

extension DDTestMonitor {
    static func _env_recreate(env: [String: String] = [:], patch: Bool = true) {
        var penv = ProcessInfo.processInfo.environment
        if patch {
            penv.merge(env) { (_, new) in new }
        } else {
            penv = env
        }
        envReader = ProcessEnvironmentReader(environment: penv)
        config = Config(env: envReader)
        DDTestMonitor.env = Environment(config: config, env: envReader, log: Log.instance)
    }
}
