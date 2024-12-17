/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import EventsExporter

internal final class Environment {
    let sourceRoot: String?
    let workspacePath: String?
    
    let platform: Platform
    let ci: CI?
    let git: Git
    
    let sessionName: String
    let testCommand: String
    
    var environment: String {
        config.environment ?? (ci != nil ? "ci" : "none")
    }
    
    var tags: [String: String] { config.tags }
    var isCI: Bool { ci != nil }
    
    let env: EnvironmentReader
    
    private let config: Config
    
    init(config: Config, env: EnvironmentReader, log: Logger, ciReaders: [CIEnvironmentReader] = Environment.ciReaders) {
        self.env = env
        self.config = config
        
        sourceRoot = env[.sourcesDir]
        
        /// Device Information
        let (runtimeName, runtimeVersion) = PlatformUtils.getRuntimeInfo()
        platform = Platform(deviceName: PlatformUtils.getDeviceName(),
                            deviceModel: PlatformUtils.getDeviceModel(),
                            osName: PlatformUtils.getRunningPlatform(),
                            osArchitecture: PlatformUtils.getPlatformArchitecture(),
                            osVersion: PlatformUtils.getDeviceVersion(),
                            runtimeName: runtimeName, runtimeVersion: runtimeVersion,
                            localization: PlatformUtils.getLocalization(),
                            vCPUCount: PlatformUtils.getCpuCount())
        
        
        let ciInfo = ciReaders.reduce(nil) { (ci, reader) in
            ci ?? (reader.isActive(env: env) ? reader.read(env: env) : nil)
        }
        ci = ciInfo?.ci
        
        var workspace = ciInfo?.ci.workspacePath
        var git: Git = ciInfo?.git ?? Git()
        
        // Read git folder information
        let gitInfo: GitInfo?

        #if targetEnvironment(simulator) || os(macOS)
        if let sourceRoot = sourceRoot ?? workspace {
            gitInfo = Self.gitInfoAt(startingPath: sourceRoot)
        } else {
            gitInfo = nil
        }
        #else
        gitInfo = nil
        #endif
        
        if let info = gitInfo,
           git.commitSHA == nil || (git.commitSHA != nil && git.commitSHA == info.commit)
        {
            git = git.extended(from: info)
            workspace = workspace ?? CI.expand(path: info.workspacePath, home: env.get(env: "HOME"))
        }
        workspacePath = workspace ?? sourceRoot
        
        self.git = git.updated(with: Environment.gitOverrides(env: env))
        
        testCommand = "test \(Bundle.testBundle?.name ?? Bundle.main.name)"
        
        if let sName = config.sessionName {
            sessionName = sName
        } else if let job = ci?.jobName {
            sessionName = "\(job)-\(testCommand)"
        } else {
            sessionName = testCommand
        }
        
        validate(log: log)
    }
    
    var ciAttributes: [String: String] {
        var ciAttributes: [String: String] = [:]
        ciAttributes[DDCITags.ciWorkspacePath] = workspacePath
        guard let ci = self.ci else { return ciAttributes }
        ciAttributes[DDCITags.ciProvider] = ci.provider
        ciAttributes[DDCITags.ciPipelineId] = ci.pipelineId
        ciAttributes[DDCITags.ciPipelineNumber] = ci.pipelineNumber
        ciAttributes[DDCITags.ciPipelineURL] = ci.pipelineURL?.spanAttribute
        ciAttributes[DDCITags.ciPipelineName] = ci.pipelineName
        ciAttributes[DDCITags.ciNodeName] = ci.nodeName
        ciAttributes[DDCITags.ciNodeLabels] = ci.nodeLabels?.description
        ciAttributes[DDCITags.ciStageName] = ci.stageName
        ciAttributes[DDCITags.ciStageName] = ci.stageName
        ciAttributes[DDCITags.ciJobName] = ci.jobName
        ciAttributes[DDCITags.ciJobURL] = ci.jobURL?.spanAttribute
        ciAttributes[DDCITags.ciEnvVars] = ##"{\##(ci.environment.map { #""\#($0.0)":"\#($0.1.spanAttribute)""# }.joined(separator: ","))}"##
        return ciAttributes
    }
    
    var gitAttributes: [String: String] {
        guard !config.disableGitInformation else { return [:] }
        var gitAttributes: [String: String] = [:]
        gitAttributes[DDGitTags.gitRepository] = git.repositoryURL?.spanAttribute
        gitAttributes[DDGitTags.gitCommit] = git.commitSHA
        gitAttributes[DDGitTags.gitBranch] = git.branch
        gitAttributes[DDGitTags.gitTag] = git.tag
        gitAttributes[DDGitTags.gitCommitMessage] = git.commitMessage
        gitAttributes[DDGitTags.gitAuthorName] = git.authorName
        gitAttributes[DDGitTags.gitAuthorEmail] = git.authorEmail
        gitAttributes[DDGitTags.gitAuthorDate] = git.authorDate?.spanAttribute
        gitAttributes[DDGitTags.gitCommitterName] = git.committerName
        gitAttributes[DDGitTags.gitCommitterEmail] = git.committerEmail
        gitAttributes[DDGitTags.gitCommitterDate] = git.committerDate?.spanAttribute
        return gitAttributes
    }
    
    var baseConfigurations: [String: String] {
        [DDOSTags.osPlatform: platform.osName,
         DDOSTags.osArchitecture: platform.osArchitecture,
         DDOSTags.osVersion: platform.osVersion,
         DDDeviceTags.deviceName: platform.deviceName,
         DDDeviceTags.deviceModel: platform.deviceModel,
         DDRuntimeTags.runtimeName: platform.runtimeName,
         DDRuntimeTags.runtimeVersion: platform.runtimeVersion,
         DDUISettingsTags.uiSettingsLocalization: platform.localization]
    }
    
    var baseMetrics: [String: Double] {
        [DDHostTags.hostVCPUCount: Double(platform.vCPUCount)]
    }
    
    private func validate(log: Logger) {
        // Warn on needed git onformation when not present
        if git.commitSHA == nil {
            log.print("could not find git commit information")
        }
        if git.repositoryURL == nil {
            log.print("could not find git repository information")
        }
        if git.branch == nil && git.tag == nil {
            log.print("could not find git branch or tag  information")
        }
        if git.commitSHA == nil || git.repositoryURL == nil || (git.branch == nil && git.tag == nil) {
            log.print("Please check: https://docs.datadoghq.com/continuous_integration/troubleshooting")
        }
        validateGitOverrides(log: log)
    }
    
    private func validateGitOverrides(log: Logger) {
        guard !config.disableGitInformation else { return }
        if env.has("DD_GIT_REPOSITORY_URL") {
            if let repo = env["DD_GIT_REPOSITORY_URL", String.self] {
                if URL(string: repo) == nil {
                    log.print("DD_GIT_REPOSITORY_URL environment variable was configured with non valid URL")
                }
            } else {
                log.print("DD_GIT_REPOSITORY_URL environment variable was configured with an empty value")
            }
        }
        if env.has("DD_GIT_COMMIT_SHA") {
            if let sha = env["DD_GIT_COMMIT_SHA", String.self] {
                if !sha.isHexNumber {
                    log.print("DD_GIT_COMMIT_SHA environment variable was configured with a non-hexadecimal string")
                } else if sha.count != 40 {
                    log.print("DD_GIT_COMMIT_SHA environment variable was configured with a value shorter than 40 character")
                }
            } else {
                log.print("DD_GIT_COMMIT_SHA environment variable was configured with an empty value")
            }
        }
    }
    
    private static func gitOverrides(env: EnvironmentReader) -> Git {
        let (branch, isTag) = Git.normalize(branchOrTag: env["DD_GIT_BRANCH"])
        return .init(
            repositoryURL: env["DD_GIT_REPOSITORY_URL"],
            branch: isTag ? nil : branch,
            tag: Git.normalize(branchOrTag: env["DD_GIT_TAG"]).0 ?? (isTag ? branch : nil),
            commitSHA: env["DD_GIT_COMMIT_SHA"],
            commitMessage: env["DD_GIT_COMMIT_MESSAGE"],
            authorName: env["DD_GIT_COMMIT_AUTHOR_NAME"],
            authorEmail: env["DD_GIT_COMMIT_AUTHOR_EMAIL"],
            authorDate: env["DD_GIT_COMMIT_AUTHOR_DATE"],
            committerName: env["DD_GIT_COMMIT_COMMITTER_NAME"],
            committerEmail: env["DD_GIT_COMMIT_COMMITTER_EMAIL"],
            committerDate: env["DD_GIT_COMMIT_COMMITTER_DATE"]
        )
    }
    
    static func gitInfoAt(startingPath: String) -> GitInfo? {
        var rootFolder = NSString(string: URL(fileURLWithPath: startingPath, isDirectory: true).path)
        while !FileManager.default.fileExists(atPath: rootFolder.appendingPathComponent(".git")) {
            if rootFolder.isEqual(to: rootFolder.deletingLastPathComponent) {
                // We reached to the top
                // Log.print("could not find .git folder at \(rootFolder)")
                break
            }
            rootFolder = rootFolder.deletingLastPathComponent as NSString
        }
        let rootDirectory = URL(fileURLWithPath: rootFolder as String, isDirectory: true)
        let gitInfo = try? GitInfo(gitFolder: rootDirectory.appendingPathComponent(".git"))
        return gitInfo
    }

    
    static var ciReaders: [CIEnvironmentReader] {
        return [
            TravisCIEnvironmentReader(), CircleCIEnvironmentReader(), JenkinsCIEnvironmentReader(),
            GitlabCIEnvironmentReader(), AppveyorCIEnvironmentReader(), AzureCIEnvironmentReader(),
            BitbucketCIEnvironmentReader(), GithubCIEnvironmentReader(), BuildkiteCIEnvironmentReader(),
            BitriseCIEnvironmentReader(), XcodeCIEnvironmentReader(), TeamcityCIEnvironmentReader(),
            CodefreshCIEnvironmentReader(), AwsCodePipelineCIEnvironmentReader(),
            AwsCodeBuildCIEnvironmentReader(), BuddyCIEnvironmentReader()
        ]
    }
    
    static var environmentCharset = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
    )
}

internal extension Environment {
    struct Platform: CustomDebugStringConvertible {
        /// Device Information
        let deviceName: String
        let deviceModel: String
        
        /// OS Information
        let osName: String
        let osArchitecture: String
        let osVersion: String
        
        /// Runtime Information
        let runtimeName: String
        let runtimeVersion: String
        
        let localization: String
        
        let vCPUCount: Int
        
        var debugDescription: String {
            """
            Platform:
              Device Name: \(deviceName)
              Device Model: \(deviceModel)
              OS Name: \(osName)
              OS Architecture: \(osArchitecture)
              OS Version: \(osVersion)
              Runtime Name: \(runtimeName)
              Runtime Version: \(runtimeVersion)
              vCPU Count: \(vCPUCount)
              Localization: \(localization)
            """
        }
    }
}


internal extension Environment {
    struct CI: CustomDebugStringConvertible {
        // ci.provider.name
        let provider: String
        
        // ci.pipeline.*
        let pipelineId: String?
        let pipelineName: String?
        let pipelineNumber: String?
        let pipelineURL: URL?
        
        // ci.stage.name
        let stageName: String?
        
        // ci.job.*
        let jobName: String?
        let jobURL: URL?
        
        // ci.workspace.path
        let workspacePath: String?
        
        // ci.node.*
        let nodeName: String?
        let nodeLabels: [String]?
        
        // additional CI environment properties
        let environment: [String: SpanAttributeConvertible]
        
        init(provider: String, pipelineId: String? = nil, pipelineName: String? = nil,
             pipelineNumber: String? = nil, pipelineURL: URL? = nil, stageName: String? = nil,
             jobName: String? = nil, jobURL: URL? = nil, workspacePath: String? = nil,
             nodeName: String? = nil, nodeLabels: [String]? = nil,
             environment: [String: SpanAttributeConvertible] = [:]
        ) {
            self.provider = provider
            self.pipelineId = pipelineId
            self.pipelineName = pipelineName
            self.pipelineNumber = pipelineNumber
            self.pipelineURL = pipelineURL
            self.stageName = stageName
            self.jobName = jobName
            self.jobURL = jobURL
            self.workspacePath = workspacePath
            self.nodeName = nodeName
            self.nodeLabels = nodeLabels
            self.environment = environment
        }
        
        static func expand(path: String?, home: String?) -> String? {
            guard var path = path else { return nil }
            if path.first == "~" && (path.count == 1 || path[path.index(after: path.startIndex)] == "/") {
                guard let home = home else { return path }
                path.removeFirst()
                path = home + path
            }
            return path
        }
        
        var debugDescription: String {
            """
            CI:
              Provider: \(provider),
              Pipeline ID: \(pipelineId ?? "")
              Pipeline Name: \(pipelineName ?? "")
              Pipeline Number: \(pipelineNumber ?? "")
              Pipeline URL: \(pipelineURL?.spanAttribute ?? "")
              Stage Name: \(stageName ?? "")
              Job Name: \(jobName ?? "")
              Job URL: \(jobURL?.spanAttribute ?? "")
              Workspace Path: \(workspacePath ?? "")
              Node Name: \(nodeName ?? "")
              Node Labels: \(nodeLabels ?? [])
              Environment: \(environment.map { "\n    \($0.key): \($0.value)" }.joined())
            """
        }
    }
}

internal extension Environment {
    struct Git: CustomDebugStringConvertible {
        // git.*
        let repositoryURL: URL?
        let branch: String?
        let tag: String?
        
        // git.commit.*
        let commitSHA: String?
        let commitMessage: String?
        
        // git.commit.author.*
        let authorName: String?
        let authorEmail: String?
        let authorDate: String?
        
        // git.commit.committer.*
        let committerName: String?
        let committerEmail: String?
        let committerDate: String?
        
        var repositoryName: String? {
            repositoryURL?.deletingPathExtension().lastPathComponent
        }
        
        init(repositoryURL: URL? = nil, branch: String? = nil, tag: String? = nil,
             commitSHA: String? = nil, commitMessage: String? = nil,
             authorName: String? = nil, authorEmail: String? = nil, authorDate: String? = nil,
             committerName: String? = nil, committerEmail: String? = nil, committerDate: String? = nil)
        {
            self.repositoryURL = repositoryURL
            self.branch = branch
            self.tag = tag
            self.commitSHA = commitSHA
            self.commitMessage = commitMessage
            self.authorName = authorName
            self.authorEmail = authorEmail
            self.authorDate = authorDate
            self.committerName = committerName
            self.committerEmail = committerEmail
            self.committerDate = committerDate
        }
        
        func extended(from info: GitInfo) -> Git {
            let (_branch, isTag) = Self.normalize(branchOrTag: info.branch)
            return Git(
                repositoryURL: repositoryURL ?? info.repository.flatMap { URL(string: $0) },
                branch: branch ?? (isTag ? nil : _branch),
                tag: tag ?? (isTag ? branch : nil),
                commitSHA: commitSHA ?? info.commit,
                commitMessage: commitMessage ?? info.commitMessage,
                authorName: authorName ?? info.authorName,
                authorEmail: authorEmail ?? info.authorEmail,
                authorDate: authorDate ?? info.authorDate,
                committerName: committerName ?? info.committerName,
                committerEmail: committerEmail ?? info.committerEmail,
                committerDate: committerDate ?? info.committerDate
            )
        }
        
        func updated(with info: Git) -> Git {
            Git(
                repositoryURL: info.repositoryURL ?? repositoryURL,
                branch: info.branch ?? branch,
                tag: info.tag ?? tag,
                commitSHA: info.commitSHA ?? commitSHA,
                commitMessage: info.commitMessage ?? commitMessage,
                authorName: info.authorName ?? authorName,
                authorEmail: info.authorEmail ?? authorEmail,
                authorDate: info.authorDate ?? authorDate,
                committerName: info.committerName ?? committerName,
                committerEmail: info.committerEmail ?? committerEmail,
                committerDate: info.committerDate ?? committerDate
            )
        }
        
        static func normalize(branchOrTag value: String?) -> (String?, Bool) {
            guard var result = value else { return (nil, false) }
            let isTag = result.contains("tags/")
            if result.hasPrefix("/") {
                result = String(result.dropFirst("/".count))
            }
            if result.hasPrefix("refs/") {
                result = String(result.dropFirst("refs/".count))
            }
            if result.hasPrefix("heads/") {
                result = String(result.dropFirst("heads/".count))
            }
            if result.hasPrefix("origin/") {
                result = String(result.dropFirst("origin/".count))
            }
            if result.hasPrefix("tags/") {
                result = String(result.dropFirst("tags/".count))
            }
            if result.hasPrefix("tag/") {
                result = String(result.dropFirst("tag/".count))
            }
            return (result, isTag)
        }
        
        var debugDescription: String {
            """
            GIT:
              Repository Name: \(repositoryName ?? "")
              Repository URL: \(repositoryURL?.spanAttribute ?? "")
              Branch: \(branch ?? "")
              Tag: \(tag ?? "")
              Commit SHA: \(commitSHA ?? "")
              Commit Message: \(commitMessage ?? "")
              Author Name: \(authorName ?? "")
              Author Email: \(authorEmail ?? "")
              Author Date: \(authorDate ?? "")
              Committer Name: \(committerName ?? "")
              Committer Email: \(committerEmail ?? "")
              Committer Date: \(committerDate ?? "")
            """
        }
    }
}

extension Environment: CustomDebugStringConvertible {
    var debugDescription: String {
        """
        Source Root: \(sourceRoot ?? "nil")
        Workspace: \(workspacePath ?? "nil")
        \(platform)
        \(ci?.debugDescription ?? "CI: nil")
        \(git)
        Attributes:
        CI: \(ciAttributes.map { "\n  \($0.key): \($0.value)" }.joined())
        GIT: \(gitAttributes.map { "\n  \($0.key): \($0.value)" }.joined())
        """
    }
}
