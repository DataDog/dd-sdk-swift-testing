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
    let disableDDSDKIOSIntegration: Bool

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

        /// Instrumentation configuration values
        let envDisableDDSDKIOSIntegration = DDEnvironmentValues.getEnvVariable("DD_DISABLE_SDKIOS_INTEGRATION") as NSString?
        disableDDSDKIOSIntegration = envDisableDDSDKIOSIntegration?.boolValue ?? false

        /// Device Information
        platformName = PlatformUtils.getRunningPlatform()
        platformArchitecture = PlatformUtils.getPlatformArchitecture()
        deviceName = PlatformUtils.getDeviceName()
        deviceModel = PlatformUtils.getDeviceModel()
        deviceVersion = PlatformUtils.getDeviceVersion()

        /// CI  values
        var branchEnv: String?
        var tagEnv: String?
        if DDEnvironmentValues.getEnvVariable("TRAVIS") != nil {
            isCi = true
            provider = "travisci"

            var repositoryEnv = DDEnvironmentValues.getEnvVariable("TRAVIS_PULL_REQUEST_SLUG")
            if branchEnv?.isEmpty ?? true {
                repositoryEnv = DDEnvironmentValues.getEnvVariable("TRAVIS_REPO_SLUG")
            }
            repository = repositoryEnv

            commit = DDEnvironmentValues.getEnvVariable("TRAVIS_GIT_COMMIT")
            workspacePath = DDEnvironmentValues.getEnvVariable("TRAVIS_BUILD_DIR")
            pipelineId = DDEnvironmentValues.getEnvVariable("TRAVIS_BUILD_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("TRAVIS_BUILD_NUMBER")
            pipelineURL = DDEnvironmentValues.getEnvVariable("TRAVIS_BUILD_WEB_URL")
            pipelineName = repositoryEnv
            jobURL = DDEnvironmentValues.getEnvVariable("TRAVIS_JOB_WEB_URL")
            tagEnv = DDEnvironmentValues.getEnvVariable("TRAVIS_TAG")
            if tagEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("TRAVIS_PULL_REQUEST_BRANCH")
                if branchEnv?.isEmpty ?? true {
                    branchEnv = DDEnvironmentValues.getEnvVariable("TRAVIS_BRANCH")
                }
            }

        } else if DDEnvironmentValues.getEnvVariable("CIRCLECI") != nil {
            isCi = true
            provider = "circleci"
            repository = DDEnvironmentValues.getEnvVariable("CIRCLE_REPOSITORY_URL")
            commit = DDEnvironmentValues.getEnvVariable("CIRCLE_SHA1")
            workspacePath = DDEnvironmentValues.getEnvVariable("CIRCLE_WORKING_DIRECTORY")
            pipelineId = DDEnvironmentValues.getEnvVariable("CIRCLE_WORKFLOW_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("CIRCLE_BUILD_NUM")
            pipelineURL = DDEnvironmentValues.getEnvVariable("CIRCLE_BUILD_URL")
            pipelineName = DDEnvironmentValues.getEnvVariable("CIRCLE_PROJECT_REPONAME")
            jobURL = pipelineURL
            tagEnv = DDEnvironmentValues.getEnvVariable("CIRCLE_TAG")
            if tagEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("CIRCLE_BRANCH")
            }

        } else if DDEnvironmentValues.getEnvVariable("JENKINS_URL") != nil {
            isCi = true
            provider = "jenkins"
            repository = DDEnvironmentValues.getEnvVariable("GIT_URL")
            commit = DDEnvironmentValues.getEnvVariable("GIT_COMMIT")
            workspacePath = DDEnvironmentValues.getEnvVariable("WORKSPACE")
            pipelineId = DDEnvironmentValues.getEnvVariable("BUILD_TAG")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BUILD_NUMBER")
            pipelineURL = DDEnvironmentValues.getEnvVariable("BUILD_URL")
            pipelineName = DDEnvironmentValues.getEnvVariable("JOB_NAME")
            jobURL = nil
            branchEnv = DDEnvironmentValues.getEnvVariable("GIT_BRANCH")
            if branchEnv?.contains("tags") ?? false {
                tagEnv = branchEnv
                branchEnv = nil
            }

        } else if DDEnvironmentValues.getEnvVariable("GITLAB_CI") != nil {
            isCi = true
            provider = "gitlab"
            repository = DDEnvironmentValues.getEnvVariable("CI_REPOSITORY_URL")
            commit = DDEnvironmentValues.getEnvVariable("CI_COMMIT_SHA")
            workspacePath = DDEnvironmentValues.getEnvVariable("CI_PROJECT_DIR")
            pipelineId = DDEnvironmentValues.getEnvVariable("CI_PIPELINE_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("CI_PIPELINE_IID")
            pipelineURL = DDEnvironmentValues.getEnvVariable("CI_PIPELINE_URL")
            pipelineName = DDEnvironmentValues.getEnvVariable("CI_PROJECT_PATH")
            jobURL = DDEnvironmentValues.getEnvVariable("CI_JOB_URL")
            branchEnv = DDEnvironmentValues.getEnvVariable("CI_COMMIT_BRANCH")
            tagEnv = DDEnvironmentValues.getEnvVariable("CI_COMMIT_TAG")
        } else if DDEnvironmentValues.getEnvVariable("APPVEYOR") != nil {
            isCi = true
            provider = "appveyor"
            let repoName = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_NAME") ?? ""
            repository = "https://github.com/\(repoName).git"
            commit = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_COMMIT")
            workspacePath = DDEnvironmentValues.getEnvVariable("APPVEYOR_BUILD_FOLDER")
            pipelineId = DDEnvironmentValues.getEnvVariable("APPVEYOR_BUILD_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("APPVEYOR_BUILD_NUMBER")
            pipelineURL = "https://ci.appveyor.com/project/\(repoName)/builds/\(pipelineId ?? "")"
            pipelineName = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_NAME")
            jobURL = pipelineURL
            branchEnv = DDEnvironmentValues.getEnvVariable("APPVEYOR_PULL_REQUEST_HEAD_REPO_BRANCH")
            if branchEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_BRANCH")
            }
            tagEnv = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_TAG_NAME")
        } else if DDEnvironmentValues.getEnvVariable("TF_BUILD") != nil {
            isCi = true
            provider = "azurepipelines"
            workspacePath = DDEnvironmentValues.getEnvVariable("BUILD_SOURCESDIRECTORY")
            pipelineId = DDEnvironmentValues.getEnvVariable("BUILD_BUILDID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BUILD_BUILDID")

            let foundationServerUri = DDEnvironmentValues.getEnvVariable("SYSTEM_TEAMFOUNDATIONSERVERURI") ?? ""
            let teamProjectId = DDEnvironmentValues.getEnvVariable("SYSTEM_TEAMPROJECTID") ?? ""
            pipelineURL = "\(foundationServerUri)/\(teamProjectId)/_build/results?buildId=\(pipelineId ?? "")&_a=summary"
            pipelineName = DDEnvironmentValues.getEnvVariable("BUILD_DEFINITIONNAME")
            let jobId = DDEnvironmentValues.getEnvVariable("SYSTEM_JOBID") ?? ""
            let taskId = DDEnvironmentValues.getEnvVariable("SYSTEM_TASKINSTANCEID") ?? ""
            jobURL = "\(foundationServerUri)/\(teamProjectId)/_build/results?buildId=\(pipelineId ?? "")&view=logs&j=\(jobId)&t=\(taskId)"

            var repositoryEnv = DDEnvironmentValues.getEnvVariable("SYSTEM_PULLREQUEST_SOURCEREPOSITORYURI")
            if repositoryEnv?.isEmpty ?? true {
                repositoryEnv = DDEnvironmentValues.getEnvVariable("BUILD_REPOSITORY_URI")
            }
            repository = repositoryEnv

            var commitEnv = DDEnvironmentValues.getEnvVariable("SYSTEM_PULLREQUEST_SOURCECOMMITID")
            if commitEnv?.isEmpty ?? true {
                commitEnv = DDEnvironmentValues.getEnvVariable("BUILD_SOURCEVERSION")
            }
            commit = commitEnv

            branchEnv = DDEnvironmentValues.getEnvVariable("SYSTEM_PULLREQUEST_SOURCEBRANCH")
            if branchEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("BUILD_SOURCEBRANCH")
            }

            if branchEnv?.contains("tags") ?? false {
                tagEnv = branchEnv
                branchEnv = nil
            }
        } else if DDEnvironmentValues.getEnvVariable("BITBUCKET_COMMIT") != nil {
            isCi = true
            provider = "bitbucketpipelines"
            repository = DDEnvironmentValues.getEnvVariable("BITBUCKET_GIT_SSH_ORIGIN")
            commit = DDEnvironmentValues.getEnvVariable("BITBUCKET_COMMIT")
            workspacePath = DDEnvironmentValues.getEnvVariable("BITBUCKET_CLONE_DIR")
            pipelineId = DDEnvironmentValues.getEnvVariable("BITBUCKET_PIPELINE_UUID")?.replacingOccurrences(of: "[{}]", with: "", options: .regularExpression)
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BITBUCKET_BUILD_NUMBER")
            pipelineName = DDEnvironmentValues.getEnvVariable("BITBUCKET_REPO_FULL_NAME")
            pipelineURL = "https://bitbucket.org/\(pipelineName ?? "")/addon/pipelines/home#!/results/\(pipelineNumber ?? ""))"
            jobURL = pipelineURL
            branchEnv = DDEnvironmentValues.getEnvVariable("BITBUCKET_BRANCH")
            tagEnv = DDEnvironmentValues.getEnvVariable("BITBUCKET_TAG")
        } else if DDEnvironmentValues.getEnvVariable("GITHUB_SHA") != nil {
            isCi = true
            provider = "github"
            repository = DDEnvironmentValues.getEnvVariable("GITHUB_REPOSITORY")
            commit = DDEnvironmentValues.getEnvVariable("GITHUB_SHA")
            workspacePath = DDEnvironmentValues.getEnvVariable("GITHUB_WORKSPACE")
            pipelineId = DDEnvironmentValues.getEnvVariable("GITHUB_RUN_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("GITHUB_RUN_NUMBER")
            pipelineURL = "\(repository ?? "")/commit/\(commit ?? "")/checks"
            pipelineName = DDEnvironmentValues.getEnvVariable("GITHUB_WORKFLOW")
            jobURL = pipelineURL
            branchEnv = DDEnvironmentValues.getEnvVariable("GITHUB_HEAD_REF")
            if branchEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("GITHUB_REF")
            }
            if branchEnv?.contains("tags") ?? false {
                tagEnv = branchEnv
                branchEnv = nil
            }
        } else if DDEnvironmentValues.getEnvVariable("BUILDKITE") != nil {
            isCi = true
            provider = "buildkite"
            repository = DDEnvironmentValues.getEnvVariable("BUILDKITE_REPO")
            commit = DDEnvironmentValues.getEnvVariable("BUILDKITE_COMMIT")
            workspacePath = DDEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_CHECKOUT_PATH")
            pipelineId = DDEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_NUMBER")
            pipelineURL = DDEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_URL")
            pipelineName = DDEnvironmentValues.getEnvVariable("BUILDKITE_PIPELINE_SLUG")
            jobURL = (pipelineURL ?? "") + "#" + (DDEnvironmentValues.getEnvVariable("BUILDKITE_JOB_ID") ?? "")
            branchEnv = DDEnvironmentValues.getEnvVariable("BUILDKITE_BRANCH")
            tagEnv = DDEnvironmentValues.getEnvVariable("BUILDKITE_TAG")
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
            tagEnv = DDEnvironmentValues.getEnvVariable("BITRISE_GIT_TAG")
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
        }

        self.branch = DDEnvironmentValues.normalizedBranchOrTag(branchOrTag: branchEnv)
        self.tag = DDEnvironmentValues.normalizedBranchOrTag(branchOrTag: tagEnv)
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

    private static func normalizedBranchOrTag(branchOrTag value: String?) -> String? {
        var result = value
        if let value = value {
            if value.hasPrefix("/refs/heads/") {
                result = String(value.dropFirst("/refs/heads/".count))
            } else if value.hasPrefix("/origin/") {
                result = String(value.dropFirst("/origin/".count))
            } else if value.hasPrefix("/tags/") {
                result = String(value.dropFirst("/tags/".count))
            }
        }
        return result
    }

    static func getEnvVariable(_ name: String) -> String? {
        guard let variable = environment[name] else {
            return nil
        }
        let returnVariable = variable.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return returnVariable.isEmpty ? nil : returnVariable
    }
}
