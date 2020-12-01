/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi

internal struct DDEnvironmentValues {
    /// Datatog Configuration values
    let ddClientToken: String?
    let ddEnvironment: String?
    let ddService: String?

    /// Instrumentation configuration values
    let disableNetworkInstrumentation: Bool
    let disableHeadersInjection: Bool
    let enableRecordPayload: Bool
    let disableStdoutInstrumentation: Bool
    let disableStderrInstrumentation: Bool
    let extraHTTPHeaders: Set<String>?
    let excludedURLS: Set<String>?

    /// Device Information
    let platformName: String
    let platformArchitecture: String
    let deviceName: String
    let deviceModel: String
    let deviceVersion: String

    /// CI  values
    let isCi: Bool
    let provider: String?
    let repository: String?
    let commit: String?
    let workspacePath: String?
    let pipelineId: String?
    let pipelineNumber: String?
    let pipelineURL: String?
    let pipelineName: String?
    let jobURL: String?
    let branch: String?
    let tag: String?

    static var environment = ProcessInfo.processInfo.environment

    init() {
        /// Datatog configuration values
        var clientToken: String?
        clientToken = DDEnvironmentValues.getEnvVariable("DATADOG_CLIENT_TOKEN")
        if clientToken == nil {
            clientToken = Bundle.main.infoDictionary?["DatadogClientToken"] as? String
        }
        ddClientToken = clientToken

        ddEnvironment = DDEnvironmentValues.getEnvVariable("DD_ENV")
        ddService = DDEnvironmentValues.getEnvVariable("DD_SERVICE")

        /// Instrumentation configuration values
        let envNetwork = DDEnvironmentValues.getEnvVariable("DD_DISABLE_NETWORK_INSTRUMENTATION") as NSString?
        disableNetworkInstrumentation = envNetwork?.boolValue ?? false

        let envHeaders = DDEnvironmentValues.getEnvVariable("DD_DISABLE_HEADERS_INJECTION") as NSString?
        disableHeadersInjection = envHeaders?.boolValue ?? false

        if let envExtraHTTPHeaders = DDEnvironmentValues.getEnvVariable("DD_INSTRUMENTATION_EXTRA_HEADERS") as String? {
            extraHTTPHeaders = Set(envExtraHTTPHeaders.components(separatedBy: CharacterSet(charactersIn: ",; ")))
        } else {
            extraHTTPHeaders = nil
        }

        if let envExcludedURLs = DDEnvironmentValues.getEnvVariable("DD_EXCLUDED_URLS") as String? {
            excludedURLS = Set(envExcludedURLs.components(separatedBy: CharacterSet(charactersIn: ",; ")))
        } else {
            excludedURLS = nil
        }

        let envRecordPayload = DDEnvironmentValues.getEnvVariable("DD_ENABLE_RECORD_PAYLOAD") as NSString?
        enableRecordPayload = envRecordPayload?.boolValue ?? false

        let envStdout = DDEnvironmentValues.getEnvVariable("DD_DISABLE_STDOUT_INSTRUMENTATION") as NSString?
        disableStdoutInstrumentation = envStdout?.boolValue ?? false

        let envStderr = DDEnvironmentValues.getEnvVariable("DD_DISABLE_STDERR_INSTRUMENTATION") as NSString?
        disableStderrInstrumentation = envStderr?.boolValue ?? false

        /// Device Information
        platformName = PlatformUtils.getRunningPlatform()
        platformArchitecture = PlatformUtils.getPlatformArchitecture()
        deviceName = PlatformUtils.getDeviceName()
        deviceModel = PlatformUtils.getDeviceModel()
        deviceVersion = PlatformUtils.getDeviceVersion()

        /// CI  values
        var branchEnv: String?
        if DDEnvironmentValues.getEnvVariable("TRAVIS") != nil {
            isCi = true
            provider = "travis"
            repository = DDEnvironmentValues.getEnvVariable("TRAVIS_REPO_SLUG")
            commit = DDEnvironmentValues.getEnvVariable("TRAVIS_COMMIT")
            workspacePath = DDEnvironmentValues.getEnvVariable("TRAVIS_BUILD_DIR")
            pipelineId = DDEnvironmentValues.getEnvVariable("TRAVIS_BUILD_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("TRAVIS_BUILD_NUMBER")
            pipelineURL = DDEnvironmentValues.getEnvVariable("TRAVIS_BUILD_WEB_URL")
            pipelineName = nil
            jobURL = DDEnvironmentValues.getEnvVariable("TRAVIS_JOB_WEB_URL")
            branchEnv = DDEnvironmentValues.getEnvVariable("TRAVIS_PULL_REQUEST_BRANCH")
            if branchEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("TRAVIS_BRANCH")
            }
            tag = nil
        } else if DDEnvironmentValues.getEnvVariable("CIRCLECI") != nil {
            isCi = true
            provider = "circleci"
            repository = DDEnvironmentValues.getEnvVariable("CIRCLE_REPOSITORY_URL")
            commit = DDEnvironmentValues.getEnvVariable("CIRCLE_SHA1")
            workspacePath = DDEnvironmentValues.getEnvVariable("CIRCLE_WORKING_DIRECTORY")
            pipelineId = nil
            pipelineNumber = DDEnvironmentValues.getEnvVariable("CIRCLE_BUILD_NUM")
            pipelineURL = DDEnvironmentValues.getEnvVariable("CIRCLE_BUILD_URL")
            pipelineName = nil
            jobURL = nil
            branchEnv = DDEnvironmentValues.getEnvVariable("CIRCLE_BRANCH")
            tag = nil
        } else if DDEnvironmentValues.getEnvVariable("JENKINS_URL") != nil {
            isCi = true
            provider = "jenkins"
            repository = DDEnvironmentValues.getEnvVariable("GIT_URL")
            commit = DDEnvironmentValues.getEnvVariable("GIT_COMMIT")
            workspacePath = DDEnvironmentValues.getEnvVariable("WORKSPACE")
            pipelineId = DDEnvironmentValues.getEnvVariable("BUILD_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BUILD_NUMBER")
            pipelineURL = DDEnvironmentValues.getEnvVariable("BUILD_URL")
            pipelineName = nil
            jobURL = DDEnvironmentValues.getEnvVariable("JOB_URL")
            branchEnv = DDEnvironmentValues.getEnvVariable("GIT_BRANCH")
            if let branchCopy = branchEnv, branchCopy.hasPrefix("origin/") {
                branchEnv = String(branchCopy.dropFirst("origin/".count))
            }
            tag = nil
        } else if DDEnvironmentValues.getEnvVariable("GITLAB_CI") != nil {
            isCi = true
            provider = "gitlab"
            repository = DDEnvironmentValues.getEnvVariable("CI_REPOSITORY_URL")
            commit = DDEnvironmentValues.getEnvVariable("CI_COMMIT_SHA")
            workspacePath = DDEnvironmentValues.getEnvVariable("CI_PROJECT_DIR")
            pipelineId = DDEnvironmentValues.getEnvVariable("CI_PIPELINE_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("CI_PIPELINE_IID")
            pipelineURL = DDEnvironmentValues.getEnvVariable("CI_PIPELINE_URL")
            pipelineName = nil
            jobURL = DDEnvironmentValues.getEnvVariable("CI_JOB_URL")
            branchEnv = DDEnvironmentValues.getEnvVariable("CI_COMMIT_BRANCH")
            if branchEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("CI_COMMIT_REF_NAME")
            }
            tag = DDEnvironmentValues.getEnvVariable("CI_COMMIT_TAG")
        } else if DDEnvironmentValues.getEnvVariable("APPVEYOR") != nil {
            isCi = true
            provider = "appveyor"
            repository = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_NAME")
            commit = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_COMMIT")
            workspacePath = DDEnvironmentValues.getEnvVariable("APPVEYOR_BUILD_FOLDER")
            pipelineId = DDEnvironmentValues.getEnvVariable("APPVEYOR_BUILD_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("APPVEYOR_BUILD_NUMBER")
            let projectSlug = DDEnvironmentValues.getEnvVariable("APPVEYOR_PROJECT_SLUG")
            pipelineURL = "https://ci.appveyor.com/project/\(projectSlug ?? "")/builds/\(pipelineId ?? "")"
            pipelineName = nil
            jobURL = nil
            branchEnv = DDEnvironmentValues.getEnvVariable("APPVEYOR_PULL_REQUEST_HEAD_REPO_BRANCH")
            if branchEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_BRANCH")
            }
            tag = nil
        } else if DDEnvironmentValues.getEnvVariable("TF_BUILD") != nil {
            isCi = true
            provider = "azurepipelines"
            workspacePath = DDEnvironmentValues.getEnvVariable("BUILD_SOURCESDIRECTORY")
            pipelineId = DDEnvironmentValues.getEnvVariable("BUILD_BUILDID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BUILD_BUILDNUMBER")

            let foundationCollectionUri = DDEnvironmentValues.getEnvVariable("SYSTEM_TEAMFOUNDATIONCOLLECTIONURI")
            let teamProject = DDEnvironmentValues.getEnvVariable("SYSTEM_TEAMPROJECT")
            pipelineURL = "\(foundationCollectionUri ?? "")/\(teamProject ?? "")/_build/results?buildId=\(pipelineId ?? "")&_a=summary"
            pipelineName = nil
            jobURL = nil
            repository = DDEnvironmentValues.getEnvVariable("BUILD_REPOSITORY_URI")

            var commitEnv = DDEnvironmentValues.getEnvVariable("SYSTEM_PULLREQUEST_SOURCECOMMITID")
            if commitEnv?.isEmpty ?? true {
                commitEnv = DDEnvironmentValues.getEnvVariable("BUILD_SOURCEVERSION")
            }
            commit = commitEnv

            branchEnv = DDEnvironmentValues.getEnvVariable("SYSTEM_PULLREQUEST_SOURCEBRANCH")
            if branchEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("BUILD_SOURCEBRANCHNAME")
            }
            if branchEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("BUILD_SOURCEBRANCH")
            }
            tag = nil
        } else if DDEnvironmentValues.getEnvVariable("BITBUCKET_COMMIT") != nil {
            isCi = true
            provider = "bitbucketpipelines"
            repository = DDEnvironmentValues.getEnvVariable("BITBUCKET_GIT_SSH_ORIGIN")
            commit = DDEnvironmentValues.getEnvVariable("BITBUCKET_COMMIT")
            workspacePath = DDEnvironmentValues.getEnvVariable("BITBUCKET_CLONE_DIR")
            pipelineId = DDEnvironmentValues.getEnvVariable("BITBUCKET_PIPELINE_UUID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BITBUCKET_BUILD_NUMBER")
            branchEnv = DDEnvironmentValues.getEnvVariable("BITBUCKET_BRANCH")
            pipelineURL = nil
            pipelineName = nil
            jobURL = nil
            tag = nil
        } else if DDEnvironmentValues.getEnvVariable("GITHUB_SHA") != nil {
            isCi = true
            provider = "github"
            repository = DDEnvironmentValues.getEnvVariable("GITHUB_REPOSITORY")
            commit = DDEnvironmentValues.getEnvVariable("GITHUB_SHA")
            workspacePath = DDEnvironmentValues.getEnvVariable("GITHUB_WORKSPACE")
            pipelineId = DDEnvironmentValues.getEnvVariable("GITHUB_RUN_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("GITHUB_RUN_NUMBER")
            pipelineURL = "\(repository ?? "")/commit/\(commit ?? "")/checks"
            pipelineName = nil
            jobURL = nil
            branchEnv = DDEnvironmentValues.getEnvVariable("GITHUB_REF")
            tag = nil
        } else if DDEnvironmentValues.getEnvVariable("TEAMCITY_VERSION") != nil {
            isCi = true
            provider = "teamcity"
            repository = DDEnvironmentValues.getEnvVariable("BUILD_VCS_URL")
            commit = DDEnvironmentValues.getEnvVariable("BUILD_VCS_NUMBER")
            workspacePath = DDEnvironmentValues.getEnvVariable("BUILD_CHECKOUTDIR")
            pipelineId = DDEnvironmentValues.getEnvVariable("BUILD_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BUILD_NUMBER")
            let serverUrl = DDEnvironmentValues.getEnvVariable("SERVER_URL")
            if let pipelineId = pipelineId, let serverUrl = serverUrl {
                pipelineURL = "\(serverUrl)/viewLog.html?buildId=\(pipelineId)"
            } else {
                pipelineURL = nil
            }
            pipelineName = nil
            jobURL = nil
            tag = nil
        } else if DDEnvironmentValues.getEnvVariable("BUILDKITE") != nil {
            isCi = true
            provider = "buildkite"
            repository = DDEnvironmentValues.getEnvVariable("BUILDKITE_REPO")
            commit = DDEnvironmentValues.getEnvVariable("BUILDKITE_COMMIT")
            workspacePath = DDEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_CHECKOUT_PATH")
            pipelineId = DDEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_NUMBER")
            pipelineURL = DDEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_URL")
            pipelineName = nil
            jobURL = nil
            branchEnv = DDEnvironmentValues.getEnvVariable("BUILDKITE_BRANCH")
            tag = nil
        } else if DDEnvironmentValues.getEnvVariable("BITRISE_BUILD_NUMBER") != nil {
            isCi = true
            provider = "bitrise"
            repository = DDEnvironmentValues.getEnvVariable("GIT_REPOSITORY_URL")

            var tempCommit = DDEnvironmentValues.getEnvVariable("BITRISE_GIT_COMMIT")
            if tempCommit?.isEmpty ?? true {
                tempCommit = DDEnvironmentValues.getEnvVariable("GIT_CLONE_COMMIT_HASH")
            }
            commit = tempCommit

            workspacePath = DDEnvironmentValues.getEnvVariable("BITRISE_SOURCE_DIR")
            pipelineId = DDEnvironmentValues.getEnvVariable("BITRISE_BUILD_SLUG")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BITRISE_BUILD_NUMBER")
            jobURL = DDEnvironmentValues.getEnvVariable("BITRISE_APP_URL")
            pipelineURL = DDEnvironmentValues.getEnvVariable("BITRISE_BUILD_URL")
            pipelineName = DDEnvironmentValues.getEnvVariable("BITRISE_APP_TITLE")
            branchEnv = DDEnvironmentValues.getEnvVariable("BITRISEIO_GIT_BRANCH_DEST")
            if branchEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("BITRISE_GIT_BRANCH")
            }
            tag = DDEnvironmentValues.getEnvVariable("BITRISE_GIT_TAG")
        } else {
            isCi = false
            provider = nil
            repository = nil
            commit = nil
            workspacePath = nil
            pipelineId = nil
            pipelineNumber = nil
            pipelineURL = nil
            pipelineName = nil
            jobURL = nil
            branchEnv = nil
            tag = nil
        }

        /// Remove /refs/heads/ from the branch when it appears. Some CI's add this info.
        if let branchCopy = branchEnv {
            if branchCopy.hasPrefix("/refs/heads/") {
                branchEnv = String(branchCopy.dropFirst("/refs/heads/".count))
            } else if branchCopy.hasPrefix("/refs/") {
                branchEnv = String(branchCopy.dropFirst("/refs/".count))
            }
        }
        self.branch = branchEnv
    }

    func addTagsToSpan(span: Span) {
        guard isCi else {
            return
        }

        setAttributeIfExist(toSpan: span, key: DDCITags.ciProvider, value: provider)
        setAttributeIfExist(toSpan: span, key: DDCITags.ciPipelineId, value: pipelineId)
        setAttributeIfExist(toSpan: span, key: DDCITags.ciPipelineNumber, value: pipelineNumber)
        setAttributeIfExist(toSpan: span, key: DDCITags.ciPipelineURL, value: pipelineURL)
        setAttributeIfExist(toSpan: span, key: DDCITags.ciPipelineName, value: pipelineName)
        setAttributeIfExist(toSpan: span, key: DDCITags.ciJobURL, value: jobURL)
        setAttributeIfExist(toSpan: span, key: DDCITags.ciWorkspacePath, value: workspacePath)

        setAttributeIfExist(toSpan: span, key: DDGitTags.gitRepository, value: repository)
        setAttributeIfExist(toSpan: span, key: DDGitTags.gitCommit, value: commit)
        setAttributeIfExist(toSpan: span, key: DDGitTags.gitCommitOld, value: commit)
        setAttributeIfExist(toSpan: span, key: DDGitTags.gitBranch, value: branch)
        setAttributeIfExist(toSpan: span, key: DDGitTags.gitTag, value: tag)
    }

    private func setAttributeIfExist(toSpan span: Span, key: String, value: String?) {
        if let value = value {
            span.setAttribute(key: key, value: value)
        }
    }

    static func getEnvVariable(_ name: String) -> String? {
        guard let variable = environment[name] else {
            return nil
        }
        let returnVariable = variable.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return returnVariable.isEmpty ? nil : returnVariable
    }

}
