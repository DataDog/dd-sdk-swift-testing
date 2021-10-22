/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
@_implementationOnly import OpenTelemetryApi

internal struct DDEnvironmentValues {
    /// Datatog Configuration values
    let ddApikeyOrClientToken: String?
    let ddEnvironment: String?
    let ddService: String?
    var ddTags = [String: String]()

    /// Instrumentation configuration values
    let disableNetworkInstrumentation: Bool
    let disableHeadersInjection: Bool
    let enableRecordPayload: Bool
    let maxPayloadSize: Int?
    let disableStdoutInstrumentation: Bool
    let disableStderrInstrumentation: Bool
    let extraHTTPHeaders: Set<String>?
    let excludedURLS: Set<String>?
    let disableDDSDKIOSIntegration: Bool
    let disableCrashHandler: Bool
    let disableTestInstrumenting: Bool

    /// OS Information
    let osName: String
    let osArchitecture: String
    let osVersion: String

    /// Device Information
    let deviceName: String
    let deviceModel: String

    /// Runtime Information
    let runtimeName: String
    let runtimeVersion: String

    /// CI  values
    let isCi: Bool
    let provider: String?
    var workspacePath: String?
    let pipelineId: String?
    let pipelineNumber: String?
    let pipelineURL: String?
    let pipelineName: String?
    let jobURL: String?
    let jobName: String?
    let stageName: String?

    /// Git values
    var repository: String?
    let branch: String?
    let tag: String?
    var commit: String?
    var commitMessage: String?
    var authorName: String?
    var authorEmail: String?
    var authorDate: String?
    var committerName: String?
    var committerEmail: String?
    var committerDate: String?

    /// Source location
    var sourceRoot: String?

    /// Environment trace Information (Used when running in an app under UI testing)
    let launchEnvironmentTraceId: String?
    let launchEnvironmentSpanId: String?

    /// Datadog Endpoint for traces
    let tracesEndpoint: String?

    /// Avoids configuring the traces exporter
    let disableTracesExporting: Bool

    /// The tracer is being tested itself
    let tracerUnderTesting: Bool
    /// The tracer send result to a localhost server (for testing purposes)
    let localTestEnvironmentPort: Int?

    /// The framework has been launched with extra debug information
    let extraDebug: Bool

    static var environment = ProcessInfo.processInfo.environment
    static var infoDictionary: [String: Any] = {
        var bundle = Bundle.allBundles.first {
            $0.bundlePath.hasSuffix(".xctest")
        }
        let dictionary = bundle?.infoDictionary ?? Bundle.main.infoDictionary
        return dictionary ?? [String: Any]()
    }()

    static let environmentCharset = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")

    init() {
        /// Datatog configuration values
        var clientToken: String?
        clientToken = DDEnvironmentValues.getEnvVariable("DATADOG_CLIENT_TOKEN")
        if clientToken == nil {
            clientToken = DDEnvironmentValues.infoDictionary["DatadogClientToken"] as? String
        }
        if clientToken == nil {
            clientToken = DDEnvironmentValues.getEnvVariable("DD_API_KEY")
        }

        ddApikeyOrClientToken = clientToken
        ddEnvironment = DDEnvironmentValues.getEnvVariable("DD_ENV")
        tracerUnderTesting = (DDEnvironmentValues.getEnvVariable("TEST_CLASS") != nil)
        let service = DDEnvironmentValues.getEnvVariable("DD_SERVICE")
        if let service = service, tracerUnderTesting {
            ddService = service + "-internal-tests"
        } else {
            ddService = service
        }

        let envLocalTestEnvironmentPort = DDEnvironmentValues.getEnvVariable("DD_LOCAL_TEST_ENVIRONMENT_PORT") as NSString?
        localTestEnvironmentPort = envLocalTestEnvironmentPort?.integerValue

        sourceRoot = DDEnvironmentValues.getEnvVariable("SRCROOT")

        if let envDDTags = DDEnvironmentValues.getEnvVariable("DD_TAGS") {
            let ddtagsEntries = envDDTags.components(separatedBy: " ")
            for entry in ddtagsEntries {
                let entryPair = entry.components(separatedBy: ":")
                guard entryPair.count == 2 else { continue }
                let key = entryPair[0].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                let value = entryPair[1].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                ddTags[key] = value
            }
        }

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

        let envMaxPayloadSize = DDEnvironmentValues.getEnvVariable("DD_MAX_PAYLOAD_SIZE") as NSString?
        maxPayloadSize = envMaxPayloadSize?.integerValue

        let envStdout = DDEnvironmentValues.getEnvVariable("DD_DISABLE_STDOUT_INSTRUMENTATION") as NSString?
        disableStdoutInstrumentation = envStdout?.boolValue ?? false

        let envStderr = DDEnvironmentValues.getEnvVariable("DD_DISABLE_STDERR_INSTRUMENTATION") as NSString?
        disableStderrInstrumentation = envStderr?.boolValue ?? false

        let envDisableDDSDKIOSIntegration = DDEnvironmentValues.getEnvVariable("DD_DISABLE_SDKIOS_INTEGRATION") as NSString?
        disableDDSDKIOSIntegration = envDisableDDSDKIOSIntegration?.boolValue ?? false

        let envDisableCrashReporting = DDEnvironmentValues.getEnvVariable("DD_DISABLE_CRASH_HANDLER") as NSString?
        disableCrashHandler = envDisableCrashReporting?.boolValue ?? false

        let envDisableTestInstrumenting = DDEnvironmentValues.getEnvVariable("DD_DISABLE_TEST_INSTRUMENTING") as NSString?
        disableTestInstrumenting = envDisableTestInstrumenting?.boolValue ?? false

        /// Device Information
        osName = PlatformUtils.getRunningPlatform()
        osArchitecture = PlatformUtils.getPlatformArchitecture()
        osVersion = PlatformUtils.getDeviceVersion()
        deviceName = PlatformUtils.getDeviceName()
        deviceModel = PlatformUtils.getDeviceModel()
        (runtimeName, runtimeVersion) = PlatformUtils.getRuntimeInfo()

        launchEnvironmentTraceId = DDEnvironmentValues.getEnvVariable("ENVIRONMENT_TRACER_TRACEID")
        launchEnvironmentSpanId = DDEnvironmentValues.getEnvVariable("ENVIRONMENT_TRACER_SPANID")

        tracesEndpoint = DDEnvironmentValues.getEnvVariable("DD_SITE") ?? DDEnvironmentValues.getEnvVariable("DD_ENDPOINT")

        let envDisableTracesExporting = DDEnvironmentValues.getEnvVariable("DD_DONT_EXPORT") as NSString?
        disableTracesExporting = envDisableTracesExporting?.boolValue ?? false

        let envExtraDebug = DDEnvironmentValues.getEnvVariable("DD_TRACE_DEBUG") as NSString?
        extraDebug = envExtraDebug?.boolValue ?? false

        /// CI  values
        var branchEnv: String?
        var tagEnv: String?
        var workspaceEnv: String?

        if DDEnvironmentValues.getEnvVariable("TRAVIS") != nil {
            isCi = true
            provider = "travisci"

            var repositoryEnv = DDEnvironmentValues.getEnvVariable("TRAVIS_PULL_REQUEST_SLUG")
            if branchEnv?.isEmpty ?? true {
                repositoryEnv = DDEnvironmentValues.getEnvVariable("TRAVIS_REPO_SLUG")
            }

            if let repo = repositoryEnv {
                repository = "https://github.com/\(repo).git"
            } else {
                repository = nil
            }

            commit = DDEnvironmentValues.getEnvVariable("TRAVIS_COMMIT")
            workspaceEnv = DDEnvironmentValues.getEnvVariable("TRAVIS_BUILD_DIR")
            pipelineId = DDEnvironmentValues.getEnvVariable("TRAVIS_BUILD_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("TRAVIS_BUILD_NUMBER")
            pipelineURL = DDEnvironmentValues.getEnvVariable("TRAVIS_BUILD_WEB_URL")
            pipelineName = repositoryEnv
            jobURL = DDEnvironmentValues.getEnvVariable("TRAVIS_JOB_WEB_URL")
            jobName = nil
            stageName = nil
            tagEnv = DDEnvironmentValues.getEnvVariable("TRAVIS_TAG")
            if tagEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("TRAVIS_PULL_REQUEST_BRANCH")
                if branchEnv?.isEmpty ?? true {
                    branchEnv = DDEnvironmentValues.getEnvVariable("TRAVIS_BRANCH")
                }
            }
            commitMessage = DDEnvironmentValues.getEnvVariable("TRAVIS_COMMIT_MESSAGE")

        } else if DDEnvironmentValues.getEnvVariable("CIRCLECI") != nil {
            isCi = true
            provider = "circleci"
            repository = DDEnvironmentValues.removingUserPassword(DDEnvironmentValues.getEnvVariable("CIRCLE_REPOSITORY_URL"))
            commit = DDEnvironmentValues.getEnvVariable("CIRCLE_SHA1")
            workspaceEnv = DDEnvironmentValues.getEnvVariable("CIRCLE_WORKING_DIRECTORY")
            pipelineId = DDEnvironmentValues.getEnvVariable("CIRCLE_WORKFLOW_ID")
            pipelineNumber = nil
            if let pipelineId = pipelineId {
                pipelineURL = "https://app.circleci.com/pipelines/workflows/\(pipelineId)"
            } else {
                pipelineURL = nil
            }
            pipelineName = DDEnvironmentValues.getEnvVariable("CIRCLE_PROJECT_REPONAME")
            jobURL = DDEnvironmentValues.getEnvVariable("CIRCLE_BUILD_URL")
            jobName = DDEnvironmentValues.getEnvVariable("CIRCLE_JOB")
            stageName = nil
            tagEnv = DDEnvironmentValues.getEnvVariable("CIRCLE_TAG")
            if tagEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("CIRCLE_BRANCH")
            }

        } else if DDEnvironmentValues.getEnvVariable("JENKINS_URL") != nil {
            isCi = true
            provider = "jenkins"
            repository = DDEnvironmentValues.removingUserPassword(DDEnvironmentValues.getEnvVariable("GIT_URL") ?? DDEnvironmentValues.getEnvVariable("GIT_URL_1"))
            commit = DDEnvironmentValues.getEnvVariable("GIT_COMMIT")
            workspaceEnv = DDEnvironmentValues.getEnvVariable("WORKSPACE")
            pipelineId = DDEnvironmentValues.getEnvVariable("BUILD_TAG")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BUILD_NUMBER")
            pipelineURL = DDEnvironmentValues.getEnvVariable("BUILD_URL")
            pipelineName = DDEnvironmentValues.filterJenkinsJobName(name: DDEnvironmentValues.getEnvVariable("JOB_NAME"),
                                                                    gitBranch: DDEnvironmentValues.normalizedBranchOrTag(DDEnvironmentValues.getEnvVariable("GIT_BRANCH")))
            jobURL = nil
            jobName = nil
            stageName = nil
            branchEnv = DDEnvironmentValues.getEnvVariable("GIT_BRANCH")

        } else if DDEnvironmentValues.getEnvVariable("GITLAB_CI") != nil {
            isCi = true
            provider = "gitlab"
            repository = DDEnvironmentValues.removingUserPassword(DDEnvironmentValues.getEnvVariable("CI_REPOSITORY_URL"))
            commit = DDEnvironmentValues.getEnvVariable("CI_COMMIT_SHA")
            workspaceEnv = DDEnvironmentValues.getEnvVariable("CI_PROJECT_DIR")
            pipelineId = DDEnvironmentValues.getEnvVariable("CI_PIPELINE_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("CI_PIPELINE_IID")
            pipelineURL = DDEnvironmentValues.getEnvVariable("CI_PIPELINE_URL")?.replacingOccurrences(of: "/-/", with: "/")
            pipelineName = DDEnvironmentValues.getEnvVariable("CI_PROJECT_PATH")
            jobURL = DDEnvironmentValues.getEnvVariable("CI_JOB_URL")
            jobName = DDEnvironmentValues.getEnvVariable("CI_JOB_NAME")
            stageName = DDEnvironmentValues.getEnvVariable("CI_JOB_STAGE")
            branchEnv = DDEnvironmentValues.getEnvVariable("CI_COMMIT_REF_NAME") ?? DDEnvironmentValues.getEnvVariable("CI_COMMIT_BRANCH")
            tagEnv = DDEnvironmentValues.getEnvVariable("CI_COMMIT_TAG")
            commitMessage = DDEnvironmentValues.getEnvVariable("CI_COMMIT_MESSAGE")
            if let gitlabAuthorComponents = DDEnvironmentValues.getEnvVariable("CI_COMMIT_AUTHOR")?.components(separatedBy: CharacterSet(charactersIn: "<>")),
               gitlabAuthorComponents.count >= 2
            {
                authorName = gitlabAuthorComponents[0].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                authorEmail = gitlabAuthorComponents[1].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            }
            authorDate = DDEnvironmentValues.getEnvVariable("CI_COMMIT_TIMESTAMP")

        } else if DDEnvironmentValues.getEnvVariable("APPVEYOR") != nil {
            isCi = true
            provider = "appveyor"
            let repoName = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_NAME") ?? ""
            repository = "https://github.com/\(repoName).git"
            commit = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_COMMIT")
            workspaceEnv = DDEnvironmentValues.getEnvVariable("APPVEYOR_BUILD_FOLDER")
            pipelineId = DDEnvironmentValues.getEnvVariable("APPVEYOR_BUILD_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("APPVEYOR_BUILD_NUMBER")
            pipelineURL = "https://ci.appveyor.com/project/\(repoName)/builds/\(pipelineId ?? "")"
            pipelineName = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_NAME")
            jobURL = pipelineURL
            jobName = nil
            stageName = nil
            branchEnv = DDEnvironmentValues.getEnvVariable("APPVEYOR_PULL_REQUEST_HEAD_REPO_BRANCH")
            if branchEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_BRANCH")
            }
            tagEnv = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_TAG_NAME")
            commitMessage = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_COMMIT_MESSAGE_EXTENDED")
            authorName = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_COMMIT_AUTHOR")
            authorEmail = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_COMMIT_AUTHOR_EMAIL")

        } else if DDEnvironmentValues.getEnvVariable("TF_BUILD") != nil {
            isCi = true
            provider = "azurepipelines"
            workspaceEnv = DDEnvironmentValues.getEnvVariable("BUILD_SOURCESDIRECTORY")
            pipelineId = DDEnvironmentValues.getEnvVariable("BUILD_BUILDID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BUILD_BUILDID")

            let foundationServerUri = DDEnvironmentValues.getEnvVariable("SYSTEM_TEAMFOUNDATIONSERVERURI") ?? ""
            let teamProjectId = DDEnvironmentValues.getEnvVariable("SYSTEM_TEAMPROJECTID") ?? ""
            pipelineURL = "\(foundationServerUri)\(teamProjectId)/_build/results?buildId=\(pipelineId ?? "")"
            pipelineName = DDEnvironmentValues.getEnvVariable("BUILD_DEFINITIONNAME")
            let jobId = DDEnvironmentValues.getEnvVariable("SYSTEM_JOBID") ?? ""
            let taskId = DDEnvironmentValues.getEnvVariable("SYSTEM_TASKINSTANCEID") ?? ""
            jobURL = "\(foundationServerUri)\(teamProjectId)/_build/results?buildId=\(pipelineId ?? "")&view=logs&j=\(jobId)&t=\(taskId)"
            jobName = DDEnvironmentValues.getEnvVariable("SYSTEM_JOBDISPLAYNAME")
            stageName = DDEnvironmentValues.getEnvVariable("SYSTEM_STAGEDISPLAYNAME")
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
            commitMessage = DDEnvironmentValues.getEnvVariable("BUILD_SOURCEVERSIONMESSAGE")
            authorName = DDEnvironmentValues.getEnvVariable("BUILD_REQUESTEDFORID")
            authorEmail = DDEnvironmentValues.getEnvVariable("BUILD_REQUESTEDFOREMAIL")

        } else if DDEnvironmentValues.getEnvVariable("BITBUCKET_BUILD_NUMBER") != nil {
            isCi = true
            provider = "bitbucket"
            repository = DDEnvironmentValues.getEnvVariable("BITBUCKET_GIT_SSH_ORIGIN")
            commit = DDEnvironmentValues.getEnvVariable("BITBUCKET_COMMIT")
            workspaceEnv = DDEnvironmentValues.getEnvVariable("BITBUCKET_CLONE_DIR")
            pipelineId = DDEnvironmentValues.getEnvVariable("BITBUCKET_PIPELINE_UUID")?.replacingOccurrences(of: "[{}]", with: "", options: .regularExpression)
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BITBUCKET_BUILD_NUMBER")
            pipelineName = DDEnvironmentValues.getEnvVariable("BITBUCKET_REPO_FULL_NAME")
            pipelineURL = "https://bitbucket.org/\(pipelineName ?? "")/addon/pipelines/home#!/results/\(pipelineNumber ?? "")"
            jobURL = pipelineURL
            jobName = nil
            stageName = nil
            branchEnv = DDEnvironmentValues.getEnvVariable("BITBUCKET_BRANCH")
            tagEnv = DDEnvironmentValues.getEnvVariable("BITBUCKET_TAG")
        } else if DDEnvironmentValues.getEnvVariable("GITHUB_WORKSPACE") != nil {
            isCi = true
            provider = "github"
            let repositoryEnv = DDEnvironmentValues.getEnvVariable("GITHUB_REPOSITORY")
            repository = "https://github.com/\(repositoryEnv ?? "").git"
            commit = DDEnvironmentValues.getEnvVariable("GITHUB_SHA")
            workspaceEnv = DDEnvironmentValues.getEnvVariable("GITHUB_WORKSPACE")
            pipelineId = DDEnvironmentValues.getEnvVariable("GITHUB_RUN_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("GITHUB_RUN_NUMBER")
            pipelineURL = "https://github.com/\(repositoryEnv ?? "")/commit/\(commit ?? "")/checks"
            pipelineName = DDEnvironmentValues.getEnvVariable("GITHUB_WORKFLOW")
            jobURL = pipelineURL
            jobName = nil
            stageName = nil
            branchEnv = DDEnvironmentValues.getEnvVariable("GITHUB_HEAD_REF")
            if branchEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("GITHUB_REF")
            }
        } else if DDEnvironmentValues.getEnvVariable("BUILDKITE") != nil {
            isCi = true
            provider = "buildkite"
            repository = DDEnvironmentValues.removingUserPassword(DDEnvironmentValues.getEnvVariable("BUILDKITE_REPO"))
            commit = DDEnvironmentValues.getEnvVariable("BUILDKITE_COMMIT")
            workspaceEnv = DDEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_CHECKOUT_PATH")
            pipelineId = DDEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_NUMBER")
            pipelineURL = DDEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_URL")
            pipelineName = DDEnvironmentValues.getEnvVariable("BUILDKITE_PIPELINE_SLUG")
            jobURL = (pipelineURL ?? "") + "#" + (DDEnvironmentValues.getEnvVariable("BUILDKITE_JOB_ID") ?? "")
            jobName = nil
            stageName = nil
            branchEnv = DDEnvironmentValues.getEnvVariable("BUILDKITE_BRANCH")
            tagEnv = DDEnvironmentValues.getEnvVariable("BUILDKITE_TAG")
            commitMessage = DDEnvironmentValues.getEnvVariable("BUILDKITE_MESSAGE")
            authorName = DDEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_AUTHOR")
            authorEmail = DDEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_AUTHOR_EMAIL")

        } else if DDEnvironmentValues.getEnvVariable("BITRISE_BUILD_NUMBER") != nil {
            isCi = true
            provider = "bitrise"
            repository = DDEnvironmentValues.getEnvVariable("GIT_REPOSITORY_URL")

            var tempCommit = DDEnvironmentValues.getEnvVariable("BITRISE_GIT_COMMIT")
            if tempCommit?.isEmpty ?? true {
                tempCommit = DDEnvironmentValues.getEnvVariable("GIT_CLONE_COMMIT_HASH")
            }
            commit = tempCommit

            workspaceEnv = DDEnvironmentValues.getEnvVariable("BITRISE_SOURCE_DIR")
            pipelineId = DDEnvironmentValues.getEnvVariable("BITRISE_BUILD_SLUG")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BITRISE_BUILD_NUMBER")
            jobURL = nil
            jobName = nil
            stageName = nil
            pipelineURL = DDEnvironmentValues.getEnvVariable("BITRISE_BUILD_URL")
            pipelineName = DDEnvironmentValues.getEnvVariable("BITRISE_TRIGGERED_WORKFLOW_ID") ??
                DDEnvironmentValues.getEnvVariable("BITRISE_APP_TITLE")
            branchEnv = DDEnvironmentValues.getEnvVariable("BITRISE_GIT_BRANCH")
            tagEnv = DDEnvironmentValues.getEnvVariable("BITRISE_GIT_TAG")

            let tempMessage = DDEnvironmentValues.getEnvVariable("BITRISE_GIT_MESSAGE")
            if tempMessage == nil {
                let messageSubject = DDEnvironmentValues.getEnvVariable("GIT_CLONE_COMMIT_MESSAGE_SUBJECT")
                let messageBody = DDEnvironmentValues.getEnvVariable("GIT_CLONE_COMMIT_MESSAGE_BODY")
                let auxMessage = ((messageSubject != nil) ? messageSubject! + ":\n" : "") + (messageBody ?? "")
                if !auxMessage.isEmpty {
                    commitMessage = auxMessage
                }
            } else {
                commitMessage = tempMessage
            }
            authorName = DDEnvironmentValues.getEnvVariable("GIT_CLONE_COMMIT_AUTHOR_NAME")
            authorEmail = DDEnvironmentValues.getEnvVariable("GIT_CLONE_COMMIT_AUTHOR_EMAIL")
            committerName = DDEnvironmentValues.getEnvVariable("GIT_CLONE_COMMIT_COMMITER_NAME")
            committerEmail = DDEnvironmentValues.getEnvVariable("GIT_CLONE_COMMIT_COMMITER_EMAIL")

        } else {
            isCi = false
            provider = nil
            repository = nil
            pipelineId = nil
            pipelineNumber = nil
            pipelineURL = nil
            pipelineName = nil
            jobURL = nil
            jobName = nil
            stageName = nil
        }

        // Read git folder information
        var gitInfo: GitInfo?

        #if targetEnvironment(simulator) || os(macOS)
        if let sourceRoot = sourceRoot ?? DDEnvironmentValues.expandingTilde(workspaceEnv) {
            gitInfo = DDEnvironmentValues.gitInfoAt(startingPath: sourceRoot)
        }
        #endif

        var gitInfoIsValid = false
        if commit == nil {
            gitInfoIsValid = true
        } else if commit == gitInfo?.commit {
            gitInfoIsValid = true
        }

        if gitInfoIsValid {
            commit = commit ?? gitInfo?.commit
            workspaceEnv = workspaceEnv ?? gitInfo?.workspacePath
            repository = repository ?? gitInfo?.repository
            branchEnv = branchEnv ?? gitInfo?.branch
            commitMessage = commitMessage ?? gitInfo?.commitMessage
            authorName = authorName ?? gitInfo?.authorName
            authorEmail = authorEmail ?? gitInfo?.authorEmail
            authorDate = authorDate ?? gitInfo?.authorDate
            committerName = committerName ?? gitInfo?.committerName
            committerEmail = committerEmail ?? gitInfo?.committerEmail
            committerDate = committerDate ?? gitInfo?.committerDate
        }

        branchEnv = DDEnvironmentValues.getEnvVariable("DD_GIT_BRANCH") ?? branchEnv
        tagEnv = DDEnvironmentValues.getEnvVariable("DD_GIT_TAG") ?? tagEnv
        if branchEnv?.contains("tags") ?? false {
            tagEnv = branchEnv
            branchEnv = nil
        }
        branch = DDEnvironmentValues.normalizedBranchOrTag(branchEnv)
        tag =  DDEnvironmentValues.normalizedBranchOrTag(tagEnv)
        repository = DDEnvironmentValues.getEnvVariable("DD_GIT_REPOSITORY_URL") ?? repository
        commit = DDEnvironmentValues.getEnvVariable("DD_GIT_COMMIT_SHA") ?? commit
        commitMessage = DDEnvironmentValues.getEnvVariable("DD_GIT_COMMIT_MESSAGE") ?? commitMessage
        authorName = DDEnvironmentValues.getEnvVariable("DD_GIT_COMMIT_AUTHOR_NAME") ?? authorName
        authorEmail = DDEnvironmentValues.getEnvVariable("DD_GIT_COMMIT_AUTHOR_EMAIL") ?? authorEmail
        authorDate = DDEnvironmentValues.getEnvVariable("DD_GIT_COMMIT_AUTHOR_DATE") ?? authorDate
        committerName = DDEnvironmentValues.getEnvVariable("DD_GIT_COMMIT_COMMITTER_NAME") ?? committerName
        committerEmail = DDEnvironmentValues.getEnvVariable("DD_GIT_COMMIT_COMMITTER_EMAIL") ?? committerEmail
        committerDate = DDEnvironmentValues.getEnvVariable("DD_GIT_COMMIT_COMMITTER_DATE") ?? committerDate

        workspacePath = DDEnvironmentValues.expandingTilde(workspaceEnv) ?? sourceRoot

        // Warn on needed git onformation when not present
        if commit == nil {
            Log.print("could not find git commit information")
        }
        if repository == nil {
            Log.print("could not find git repository information")
        }
        if branch == nil && tag == nil {
            Log.print("could not find git branch or tag  information")
        }
        if commit == nil || repository == nil || (branch == nil && tag == nil) {
            Log.print("Please check: https://docs.datadoghq.com/continuous_integration/troubleshooting")
        }
    }

    func addTagsToSpan(span: Span) {
        // Add the user defined tags
        ddTags.forEach {
            let value: String
            if $0.value.hasPrefix("$") {
                var auxValue = $0.value.dropFirst()
                let environmentPrefix = auxValue.unicodeScalars.prefix(while: { DDEnvironmentValues.environmentCharset.contains($0) })
                if let environmentValue = DDEnvironmentValues.getEnvVariable(String(environmentPrefix)),
                   let environmentRange = auxValue.range(of: String(environmentPrefix))
                {
                    auxValue.replaceSubrange(environmentRange, with: environmentValue)
                    value = String(auxValue)
                } else {
                    value = $0.value
                }
            } else {
                value = $0.value
            }
            setAttributeIfExist(toSpan: span, key: $0.key, value: value)
        }

        setAttributeIfExist(toSpan: span, key: DDCITags.ciWorkspacePath, value: workspacePath)

        let disableGit = (DDEnvironmentValues.getEnvVariable("DD_DISABLE_GIT_INFORMATION") as NSString?)?.boolValue ?? false
        if !disableGit {
            setAttributeIfExist(toSpan: span, key: DDGitTags.gitRepository, value: repository)
            setAttributeIfExist(toSpan: span, key: DDGitTags.gitCommit, value: commit)
            setAttributeIfExist(toSpan: span, key: DDGitTags.gitBranch, value: branch)
            setAttributeIfExist(toSpan: span, key: DDGitTags.gitTag, value: tag)

            setAttributeIfExist(toSpan: span, key: DDGitTags.gitCommitMessage, value: commitMessage)
            setAttributeIfExist(toSpan: span, key: DDGitTags.gitAuthorName, value: authorName)
            setAttributeIfExist(toSpan: span, key: DDGitTags.gitAuthorEmail, value: authorEmail)
            setAttributeIfExist(toSpan: span, key: DDGitTags.gitAuthorDate, value: authorDate)
            setAttributeIfExist(toSpan: span, key: DDGitTags.gitCommitterName, value: committerName)
            setAttributeIfExist(toSpan: span, key: DDGitTags.gitCommitterEmail, value: committerEmail)
            setAttributeIfExist(toSpan: span, key: DDGitTags.gitCommitterDate, value: committerDate)
        }

        if !isCi {
            return
        }

        setAttributeIfExist(toSpan: span, key: DDCITags.ciProvider, value: provider ?? "local development")
        setAttributeIfExist(toSpan: span, key: DDCITags.ciPipelineId, value: pipelineId)
        setAttributeIfExist(toSpan: span, key: DDCITags.ciPipelineNumber, value: pipelineNumber)
        setAttributeIfExist(toSpan: span, key: DDCITags.ciPipelineURL, value: pipelineURL)
        setAttributeIfExist(toSpan: span, key: DDCITags.ciPipelineName, value: pipelineName)
        setAttributeIfExist(toSpan: span, key: DDCITags.ciStageName, value: stageName)
        setAttributeIfExist(toSpan: span, key: DDCITags.ciJobName, value: jobName)
        setAttributeIfExist(toSpan: span, key: DDCITags.ciJobURL, value: jobURL)
    }

    private func setAttributeIfExist(toSpan span: Span, key: String, value: String?) {
        if let value = value {
            span.setAttribute(key: key, value: value)
        }
    }

    private static func normalizedBranchOrTag(_ value: String?) -> String? {
        var result = value

        if let aux = result, aux.hasPrefix("/") {
            result = String(aux.dropFirst("/".count))
        }
        if let aux = result, aux.hasPrefix("refs/") {
            result = String(aux.dropFirst("refs/".count))
        }
        if let aux = result, aux.hasPrefix("heads/") {
            result = String(aux.dropFirst("heads/".count))
        }
        if let aux = result, aux.hasPrefix("origin/") {
            result = String(aux.dropFirst("origin/".count))
        }
        if let aux = result, aux.hasPrefix("tags/") {
            result = String(aux.dropFirst("tags/".count))
        }
        if let aux = result, aux.hasPrefix("tag/") {
            result = String(aux.dropFirst("tag/".count))
        }
        return result
    }

    private static func expandingTilde(_ path: String?) -> String? {
        var result = path
        if let aux = result {
            if aux == "~" {
                result = DDEnvironmentValues.getEnvVariable("HOME")
            } else if aux.hasPrefix("~"), let home = DDEnvironmentValues.getEnvVariable("HOME") {
                result = aux.replacingOccurrences(of: "~/", with: home + "/")
            }
        }
        return result
    }

    private static func removingUserPassword(_ string: String?) -> String? {
        var result = string
        if let string = string, let url = URL(string: string) {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.user = nil
            components?.password = nil
            result = components?.string
        }
        return result
    }

    private static func filterJenkinsJobName(name: String?, gitBranch: String?) -> String? {
        guard let name = name else { return nil }
        var jobNameNoBranch = name

        if let gitBranch = gitBranch {
            jobNameNoBranch = name.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "/" + gitBranch, with: "")
        }

        var configurations = [String: String]()
        let jobNameParts = jobNameNoBranch.split(separator: "/")
        if jobNameParts.count > 1, jobNameParts[1].contains("=") {
            let configStr = jobNameParts[1].lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let configsKeyValue = configStr.split(separator: ",")
            configsKeyValue.forEach {
                let keyValue = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: "=")
                configurations[String(keyValue[0])] = String(keyValue[1])
            }
        }

        if configurations.isEmpty {
            return jobNameNoBranch
        } else {
            return String(jobNameParts[0])
        }
    }

    static func getEnvVariable(_ name: String) -> String? {
        guard let variable = environment[name] ?? DDEnvironmentValues.infoDictionary[name] as? String
        else {
            return nil
        }
        let returnVariable = variable.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return returnVariable.isEmpty ? nil : returnVariable
    }

    func getRepositoryName() -> String? {
        guard let repository = repository,
              let repoURL = URL(string: repository)
        else {
            return nil
        }
        return repoURL.deletingPathExtension().lastPathComponent
    }

    static func gitInfoAt(startingPath: String) -> GitInfo? {
        var rootFolder = NSString(string: URL(fileURLWithPath: startingPath).path)
        while !FileManager.default.fileExists(atPath: rootFolder.appendingPathComponent(".git")) {
            if rootFolder.isEqual(to: rootFolder.deletingLastPathComponent) {
                // We reached to the top
                Log.print("could not find .git folder at \(rootFolder)")
                break
            }
            rootFolder = rootFolder.deletingLastPathComponent as NSString
        }
        let rootDirectory = URL(fileURLWithPath: rootFolder as String, isDirectory: true)
        let gitInfo = try? GitInfo(gitFolder: rootDirectory.appendingPathComponent(".git"))
        return gitInfo
    }
}
