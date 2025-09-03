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
    
    func testAddTagsToMetadata() {
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

        let metadata = SpanMetadata(libraryVersion: "1.0", env: createEnv(testEnvironment), capabilities: .allCapabilities)
        
        for type in SpanMetadata.SpanType.allTest {
            XCTAssertEqual(metadata[string: type, DDCITags.ciProvider], "jenkins")
            XCTAssertEqual(metadata[string: type, DDCITags.ciPipelineId], "pipeline1")
            XCTAssertEqual(metadata[string: type, DDCITags.ciPipelineNumber], "45")
            XCTAssertEqual(metadata[string: type, DDCITags.ciPipelineURL], "http://jenkins.com/build")
            XCTAssertEqual(metadata[string: type, DDCITags.ciPipelineName], "job1")
            XCTAssertEqual(metadata[string: type, DDCITags.ciWorkspacePath], "/build")
            XCTAssertEqual(metadata[string: type, DDGitTags.gitRepository], "/test/repo")
            XCTAssertEqual(metadata[string: type, DDGitTags.gitCommit], "37e376448b0ac9b7f54404")
            XCTAssertEqual(metadata[string: type, DDGitTags.gitBranch], "develop")
            
            XCTAssertEqual(metadata[string: type, DDOSTags.osArchitecture], PlatformUtils.getPlatformArchitecture())
            XCTAssertEqual(metadata[string: type, DDOSTags.osPlatform], PlatformUtils.getRunningPlatform())
            XCTAssertEqual(metadata[string: type, DDOSTags.osVersion], PlatformUtils.getDeviceVersion())
            XCTAssertEqual(metadata[string: type, DDDeviceTags.deviceModel], PlatformUtils.getDeviceModel())
            XCTAssertEqual(metadata[string: type, DDDeviceTags.deviceName], PlatformUtils.getDeviceName())
            XCTAssertEqual(metadata[string: type, DDRuntimeTags.runtimeName], "Xcode")
            XCTAssertEqual(metadata[string: type, DDRuntimeTags.runtimeVersion], PlatformUtils.getXcodeVersion())
            XCTAssertEqual(metadata[string: type, DDUISettingsTags.uiSettingsLocalization], PlatformUtils.getLocalization())
        }
        
        XCTAssertEqual(metadata[string: .test, DDLibraryCapabilitiesTags.testImpactAnalysis], "1")
        XCTAssertEqual(metadata[string: .test, DDLibraryCapabilitiesTags.earlyFlakeDetection], "1")
        XCTAssertEqual(metadata[string: .test, DDLibraryCapabilitiesTags.autoTestRetries], "1")
        XCTAssertEqual(metadata[string: .test, DDLibraryCapabilitiesTags.impactedTests], "1")
        XCTAssertEqual(metadata[string: .test, DDLibraryCapabilitiesTags.failFastTestOrder], "1")
        XCTAssertEqual(metadata[string: .test, DDLibraryCapabilitiesTags.testManagementQuarantine], "1")
        XCTAssertEqual(metadata[string: .test, DDLibraryCapabilitiesTags.testManagementDisable], "1")
        XCTAssertEqual(metadata[string: .test, DDLibraryCapabilitiesTags.testManagementAttemptToFix], "2")
    }

    func testWhenNotRunningInCI_CITagsAreNotAdded() {
        var testEnvironment = [String: SpanAttributeConvertible]()
        testEnvironment["SRCROOT"] = ProcessInfo.processInfo.environment["SRCROOT"]

        let metadata = SpanMetadata(libraryVersion: "1.0", env: createEnv(testEnvironment), capabilities: .libraryCapabilities)
        
        for type in SpanMetadata.SpanType.allTest {
            XCTAssertNotNil(metadata[type, DDCITags.ciWorkspacePath])
            XCTAssertNil(metadata[type, DDCITags.ciProvider])
        }
    }
    
    func testSessionName() {
        let emptyEnv = createEnv([:])
        let metadata1 = SpanMetadata(libraryVersion: "1.0",
                                     env: createEnv([EnvironmentKey.sessionName.rawValue: "MyCoolSession"]),
                                     capabilities: .libraryCapabilities)
        let metadata2 = SpanMetadata(libraryVersion: "1.0",
                                     env: createEnv(["GITLAB_CI": "1",
                                                     "CI_JOB_NAME": "job1"]),
                                     capabilities: .libraryCapabilities)
        let metadata3 = SpanMetadata(libraryVersion: "1.0", env: emptyEnv, capabilities: .libraryCapabilities)
        
        for type in SpanMetadata.SpanType.allTest {
            XCTAssertEqual(metadata1[string: type, DDTestSessionTags.testSessionName], "MyCoolSession")
            XCTAssertEqual(metadata2[string: type, DDTestSessionTags.testSessionName], "job1-\(emptyEnv.testCommand)")
            XCTAssertEqual(metadata3[string: type, DDTestSessionTags.testSessionName], emptyEnv.testCommand)
        }
        
    }
    
    func testService() {
        let emptyEnv = createEnv([:])
        let metadata1 = SpanMetadata(libraryVersion: "1.0",
                                     env: createEnv([EnvironmentKey.service.rawValue: "MyCoolService"]),
                                     capabilities: .libraryCapabilities)
        let metadata2 = SpanMetadata(libraryVersion: "1.0", env: emptyEnv, capabilities: .libraryCapabilities)
        
        for type in SpanMetadata.SpanType.allTest {
            XCTAssertEqual(metadata1[string: type, DDTags.isUserProvidedService], "true")
            XCTAssertEqual(metadata2[string: type, DDTags.isUserProvidedService], "false")
        }
    }

    func testAddCustomTagsWithDDTags() {
        var testEnvironment = [String: SpanAttributeConvertible]()
        testEnvironment["DD_TAGS"] = "key1:value1 key2:value2 key3:value3 keyFoo:$FOO keyFooFoo:$FOOFOO keyMix:$FOO-v1"
        testEnvironment["FOO"] = "BAR"
        testEnvironment["SRCROOT"] = ProcessInfo.processInfo.environment["SRCROOT"]
        
        let metadata = SpanMetadata(libraryVersion: "1.0", env: createEnv(testEnvironment), capabilities: .libraryCapabilities)
        XCTAssertEqual(metadata[string: .test, "key1"], "value1")
        XCTAssertEqual(metadata[string: .test, "key2"], "value2")
        XCTAssertEqual(metadata[string: .test, "key3"], "value3")
        XCTAssertEqual(metadata[string: .test, "keyFoo"], "BAR")
        XCTAssertEqual(metadata[string: .test, "keyFooFoo"], "$FOOFOO")
        XCTAssertEqual(metadata[string: .test, "keyMix"], "BAR-v1")
        XCTAssertNotNil(metadata[string: .test, DDCITags.ciWorkspacePath])
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
    
    // MARK: - GitHub CI Pull Request Tests
    func testGitHubCIPullRequestDetectionWithValidEventFile() throws {
        // Use the actual github-event.json fixture file
        let jsonURL = Bundle(for: type(of: self)).resourceURL!
            .appendingPathComponent("fixtures")
            .appendingPathComponent("ci")
            .appendingPathComponent("github-event.json")
        
        var testEnvironment = [String: SpanAttributeConvertible]()
        testEnvironment["GITHUB_ACTIONS"] = "true"
        testEnvironment["GITHUB_REPOSITORY"] = "test-owner/test-repo"
        testEnvironment["GITHUB_SHA"] = "df289512a51123083a8e6931dd6f57bb3883d4c4"
        testEnvironment["GITHUB_BASE_REF"] = "main"  // Indicates pull request
        testEnvironment["GITHUB_EVENT_PATH"] = jsonURL.path
        testEnvironment["GITHUB_HEAD_REF"] = "test-branch"
        testEnvironment["GITHUB_RUN_ID"] = "123456789"
        
        let env = createEnv(testEnvironment)
        
        // Verify basic GitHub CI detection
        XCTAssertNotNil(env.ci)
        XCTAssertEqual(env.ci?.provider, "github")
        
        // Verify pull request metadata is extracted
        XCTAssertEqual(env.git.pullRequestHeadSha, "df289512a51123083a8e6931dd6f57bb3883d4c4")
        XCTAssertEqual(env.git.pullRequestBaseBranch, "main")
        XCTAssertEqual(env.git.pullRequestBaseBranchSha, "52e0974c74d41160a03d59ddc73bb9f5adab054b")
        
        // Verify span attributes include pull request data
        let metadata = SpanMetadata(libraryVersion: "1.0", env: env, capabilities: .libraryCapabilities)
        XCTAssertEqual(metadata[string: .test, DDGitTags.gitCommitHeadSha], "df289512a51123083a8e6931dd6f57bb3883d4c4")
        XCTAssertEqual(metadata[string: .test, DDGitTags.gitPullRequestBaseBranch], "main")
        XCTAssertEqual(metadata[string: .test, DDGitTags.gitPullRequestBaseBranchSha], "52e0974c74d41160a03d59ddc73bb9f5adab054b")
    }
    
    func testGitHubCIMissingEventPathFile() {
        var testEnvironment = [String: SpanAttributeConvertible]()
        testEnvironment["GITHUB_ACTIONS"] = "true"
        testEnvironment["GITHUB_REPOSITORY"] = "test-owner/test-repo"
        testEnvironment["GITHUB_SHA"] = "df289512a51123083a8e6931dd6f57bb3883d4c4"
        testEnvironment["GITHUB_BASE_REF"] = "main"  // Indicates pull request
        // GITHUB_EVENT_PATH is missing
        testEnvironment["GITHUB_HEAD_REF"] = "test-branch"
        testEnvironment["GITHUB_RUN_ID"] = "123456789"
        
        let env = createEnv(testEnvironment)
        
        // Verify basic GitHub CI detection still works
        XCTAssertNotNil(env.ci)
        XCTAssertEqual(env.ci?.provider, "github")
        
        // Verify pull request metadata gracefully fails
        XCTAssertNil(env.git.pullRequestHeadSha)
        XCTAssertEqual(env.git.pullRequestBaseBranch, "main")  // Still set from GITHUB_BASE_REF
        XCTAssertNil(env.git.pullRequestBaseBranchSha)
    }
    
    func testGitHubCIInvalidEventFile() throws {
        // Create a temporary file with invalid JSON
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid-github-event.json")
        try "{ invalid json }".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        var testEnvironment = [String: SpanAttributeConvertible]()
        testEnvironment["GITHUB_ACTIONS"] = "true"
        testEnvironment["GITHUB_REPOSITORY"] = "test-owner/test-repo"
        testEnvironment["GITHUB_SHA"] = "df289512a51123083a8e6931dd6f57bb3883d4c4"
        testEnvironment["GITHUB_BASE_REF"] = "main"  // Indicates pull request
        testEnvironment["GITHUB_EVENT_PATH"] = tempFile.path
        testEnvironment["GITHUB_HEAD_REF"] = "test-branch"
        testEnvironment["GITHUB_RUN_ID"] = "123456789"
        
        let env = createEnv(testEnvironment)
        
        // Verify basic GitHub CI detection still works
        XCTAssertNotNil(env.ci)
        XCTAssertEqual(env.ci?.provider, "github")
        
        // Verify pull request metadata gracefully fails
        XCTAssertNil(env.git.pullRequestHeadSha)
        XCTAssertEqual(env.git.pullRequestBaseBranch, "main")  // Still set from GITHUB_BASE_REF
        XCTAssertNil(env.git.pullRequestBaseBranchSha)
    }
    
    func testGitHubCIEnvironmentOverrides() {
        var testEnvironment = [String: SpanAttributeConvertible]()
        testEnvironment["GITHUB_ACTIONS"] = "true"
        testEnvironment["GITHUB_REPOSITORY"] = "test-owner/test-repo"
        testEnvironment["GITHUB_SHA"] = "df289512a51123083a8e6931dd6f57bb3883d4c4"
        // Test environment override capabilities
        testEnvironment["DD_GIT_COMMIT_HEAD_SHA"] = "override-head-sha"
        testEnvironment["DD_GIT_PULL_REQUEST_BASE_BRANCH"] = "override-base-branch"
        testEnvironment["DD_GIT_PULL_REQUEST_BASE_BRANCH_SHA"] = "override-base-sha"
        
        let env = createEnv(testEnvironment)
        
        // Verify environment overrides work
        XCTAssertEqual(env.git.pullRequestHeadSha, "override-head-sha")
        XCTAssertEqual(env.git.pullRequestBaseBranch, "override-base-branch")
        XCTAssertEqual(env.git.pullRequestBaseBranchSha, "override-base-sha")
        
        // Verify span attributes reflect overrides
        let metadata = SpanMetadata(libraryVersion: "1.0", env: env, capabilities: .libraryCapabilities)
        XCTAssertEqual(metadata[string: .test, DDGitTags.gitCommitHeadSha], "override-head-sha")
        XCTAssertEqual(metadata[string: .test, DDGitTags.gitPullRequestBaseBranch], "override-base-branch")
        XCTAssertEqual(metadata[string: .test, DDGitTags.gitPullRequestBaseBranchSha], "override-base-sha")
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
            
            let metadata = SpanMetadata(libraryVersion: "1.0", env: createEnv(spec[0]), capabilities: .libraryCapabilities)

            spec[1].forEach {
                let data = metadata[string: .test, $0.key]
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
