/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

internal final class Environment {
    let sourceRoot: String?
    let workspacePath: String?
    
    let platform: Platform
    let ci: CI?
    let git: Git
    
    let sessionName: String
    let testCommand: String
    let service: String
    let isUserProvidedService: Bool
    
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
           git.commit?.sha == nil || (git.commit?.sha != nil && git.commit?.sha == info.commit)
        {
            git = git.extended(from: info)
            workspace = workspace ?? CI.expand(path: info.workspacePath, home: env.get(env: "HOME"))
        }
        workspacePath = workspace ?? sourceRoot
        
        #if targetEnvironment(simulator) || os(macOS)
        if let sourceRoot = sourceRoot ?? workspace,
           let head = git.commitHead?.sha,
           let info = Self.mergeHeadInfo(headSha: head, workspace: sourceRoot, log: log)
        {
            git = git.updated(with: info)
        }
        #endif
        
        self.git = git.updated(with: Environment.gitOverrides(env: env))
        
        testCommand = "test \(Bundle.testBundle?.name ?? Bundle.main.name)"
        
        if let sName = config.sessionName {
            sessionName = sName
        } else if let job = ci?.jobName {
            sessionName = "\(job)-\(testCommand)"
        } else {
            sessionName = testCommand
        }
        
        if let service = config.service {
            self.service = service
            self.isUserProvidedService = true
        } else {
            self.service = git.repositoryName ?? "unknown-swift-repo"
            self.isUserProvidedService = false
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
        ciAttributes[DDCITags.ciJobId] = ci.jobId
        ciAttributes[DDCITags.ciJobName] = ci.jobName
        ciAttributes[DDCITags.ciJobURL] = ci.jobURL?.spanAttribute
        ciAttributes[DDCITags.ciEnvVars] = ##"{\##(ci.environment.map { #""\#($0.0)":"\#($0.1.spanAttribute)""# }.joined(separator: ","))}"##
        ciAttributes[DDCITags.prNumber] = ci.prNumber
        return ciAttributes
    }
    
    var gitAttributes: [String: String] {
        guard !config.disableGitInformation else { return [:] }
        var gitAttributes: [String: String] = [:]
        gitAttributes[DDGitTags.gitRepository] = git.repositoryURL?.spanAttribute
        gitAttributes[DDGitTags.gitBranch] = git.branch
        gitAttributes[DDGitTags.gitTag] = git.tag
        gitAttributes[DDGitTags.gitCommitSha] = git.commit?.sha
        gitAttributes[DDGitTags.gitCommitMessage] = git.commit?.message
        gitAttributes[DDGitTags.gitAuthorName] = git.commit?.author?.name
        gitAttributes[DDGitTags.gitAuthorEmail] = git.commit?.author?.email
        gitAttributes[DDGitTags.gitAuthorDate] = git.commit?.author?.date?.spanAttribute
        gitAttributes[DDGitTags.gitCommitterName] = git.commit?.committer?.name
        gitAttributes[DDGitTags.gitCommitterEmail] = git.commit?.committer?.email
        gitAttributes[DDGitTags.gitCommitterDate] = git.commit?.committer?.date?.spanAttribute
        gitAttributes[DDGitTags.gitCommitHeadSha] = git.commitHead?.sha
        gitAttributes[DDGitTags.gitCommitHeadMessage] = git.commitHead?.message
        gitAttributes[DDGitTags.gitCommitHeadAuthorName] = git.commitHead?.author?.name
        gitAttributes[DDGitTags.gitCommitHeadAuthorEmail] = git.commitHead?.author?.email
        gitAttributes[DDGitTags.gitCommitHeadAuthorDate] = git.commitHead?.author?.date?.spanAttribute
        gitAttributes[DDGitTags.gitCommitHeadCommitterName] = git.commitHead?.committer?.name
        gitAttributes[DDGitTags.gitCommitHeadCommitterEmail] = git.commitHead?.committer?.email
        gitAttributes[DDGitTags.gitCommitHeadCommitterDate] = git.commitHead?.committer?.date?.spanAttribute
        gitAttributes[DDGitTags.gitPullRequestBaseBranch] = git.pullRequestBaseBranch?.name
        gitAttributes[DDGitTags.gitPullRequestBaseBranchSha] = git.pullRequestBaseBranch?.sha
        gitAttributes[DDGitTags.gitPullRequestBaseBranchHeadSha] = git.pullRequestBaseBranch?.headSha
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
        if git.commit?.sha == nil {
            log.print("could not find git commit information")
        }
        if git.repositoryURL == nil {
            log.print("could not find git repository information")
        }
        if git.branch == nil && git.tag == nil {
            log.print("could not find git branch or tag information")
        }
        if git.commit?.sha == nil || git.repositoryURL == nil || (git.branch == nil && git.tag == nil) {
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
            commit: .maybe(sha: env["DD_GIT_COMMIT_SHA"],
                           message: env["DD_GIT_COMMIT_MESSAGE"],
                           author: .maybe(name: env["DD_GIT_COMMIT_AUTHOR_NAME"],
                                          email: env["DD_GIT_COMMIT_AUTHOR_EMAIL"],
                                          date: env["DD_GIT_COMMIT_AUTHOR_DATE"]),
                           committer: .maybe(name: env["DD_GIT_COMMIT_COMMITTER_NAME"],
                                             email: env["DD_GIT_COMMIT_COMMITTER_EMAIL"],
                                             date: env["DD_GIT_COMMIT_COMMITTER_DATE"])),
            commitHead: .maybe(sha: env["DD_GIT_COMMIT_HEAD_SHA"]),
            pullRequestBaseBranch: .maybe(name: env["DD_GIT_PULL_REQUEST_BASE_BRANCH"], sha: env["DD_GIT_PULL_REQUEST_BASE_BRANCH_SHA"])
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
    
    static func mergeHeadInfo(headSha: String, workspace: String, log: Logger) -> Git? {
        let git = { (cmd: String) -> String? in
            Spawn.output(try: "git -C \"\(workspace)\" \(cmd)", log: log)
        }
        // Unshallow one commit
        guard git("fetch --deepen=1 --update-shallow --filter=blob:none --recurse-submodules=no") != nil else {
            return nil
        }
        guard let message = git("log -n 1 --format=%B \(headSha)") else {
            return nil
        }
        guard let info = git("show -s --format=%an\t%ae\t%at\t%cn\t%ce\t%ct \(headSha)") else {
            return nil
        }
        let fields = info.components(separatedBy: "\t")
        guard fields.count >= 6 else { return nil }
        let auhorDate = UInt(fields[2]).map { Date(timeIntervalSince1970: Double($0)) }?.spanAttribute ?? fields[1]
        let commiterDate = UInt(fields[5]).map { Date(timeIntervalSince1970: Double($0)) }?.spanAttribute ?? fields[5]
        return Git(
            commitHead: .init(sha: headSha,
                              message: message,
                              author: .init(name: fields[0],
                                            email: fields[1],
                                            date: auhorDate),
                              committer: .init(name: fields[3],
                                               email: fields[4],
                                               date: commiterDate))
        )
    }

    
    static var ciReaders: [CIEnvironmentReader] {
        return [
            TravisCIEnvironmentReader(), CircleCIEnvironmentReader(), JenkinsCIEnvironmentReader(),
            GitlabCIEnvironmentReader(), AppveyorCIEnvironmentReader(), AzureCIEnvironmentReader(),
            BitbucketCIEnvironmentReader(), GithubCIEnvironmentReader(), BuildkiteCIEnvironmentReader(),
            BitriseCIEnvironmentReader(), XcodeCIEnvironmentReader(), TeamcityCIEnvironmentReader(),
            CodefreshCIEnvironmentReader(), AwsCodePipelineCIEnvironmentReader(),
            AwsCodeBuildCIEnvironmentReader(), BuddyCIEnvironmentReader(), DroneCIEnvironmentReader()
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
        let jobId: String?
        let jobName: String?
        let jobURL: URL?
        
        // ci.workspace.path
        let workspacePath: String?
        
        // ci.node.*
        let nodeName: String?
        let nodeLabels: [String]?
        
        // pr.number. it's here because it's a PR info
        let prNumber: String?
        
        // additional CI environment properties
        let environment: [String: SpanAttributeConvertible]
        
        init(provider: String, pipelineId: String? = nil, pipelineName: String? = nil,
             pipelineNumber: String? = nil, pipelineURL: URL? = nil, stageName: String? = nil,
             jobId: String? = nil, jobName: String? = nil, jobURL: URL? = nil,
             workspacePath: String? = nil, nodeName: String? = nil, nodeLabels: [String]? = nil,
             prNumber: String? = nil, environment: [String: SpanAttributeConvertible] = [:]
        ) {
            self.provider = provider
            self.pipelineId = pipelineId
            self.pipelineName = pipelineName
            self.pipelineNumber = pipelineNumber
            self.pipelineURL = pipelineURL
            self.stageName = stageName
            self.jobId = jobId
            self.jobName = jobName
            self.jobURL = jobURL
            self.workspacePath = workspacePath
            self.nodeName = nodeName
            self.nodeLabels = nodeLabels
            self.prNumber = prNumber
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
        struct AuthorInfo: CustomDebugStringConvertible {
            let name: String?
            let email: String?
            let date: String?
            
            init(name: String? = nil, email: String? = nil, date: String? = nil) {
                self.name = name
                self.email = email
                self.date = date
            }
            
            func updated(name: String? = nil, email: String? = nil, date: String? = nil) -> Self {
                .init(name: name ?? self.name, email: email ?? self.email, date: date ?? self.date)
            }
            
            func updated(with info: Self?) -> Self {
                updated(name: info?.name, email: info?.email, date: info?.date)
            }
            
            func extended(name: String? = nil, email: String? = nil, date: String? = nil) -> Self {
                .init(name: self.name ?? name, email: self.email ?? email, date: self.date ?? date)
            }
            
            func extended(from info: Self?) -> Self {
                extended(name: info?.name, email: info?.email, date: info?.date)
            }
            
            var debugDescription: String {
                "(name: \(name ?? ""), email: \(email ?? ""), date: \(date ?? ""))"
            }
            
            static func maybe(name: String? = nil, email: String? = nil, date: String? = nil) -> Self? {
                guard name != nil || email != nil || date != nil else {
                    return nil
                }
                return .init(name: name, email: email, date: date)
            }
        }
        
        struct CommitInfo: CustomDebugStringConvertible {
            let sha: String?
            let message: String?
            let author: AuthorInfo?
            let committer: AuthorInfo?
            
            init(sha: String? = nil, message: String? = nil, author: AuthorInfo? = nil, committer: AuthorInfo? = nil) {
                self.sha = sha
                self.message = message
                self.author = author
                self.committer = committer
            }
            
            func updated(sha: String? = nil, message: String? = nil, author: AuthorInfo? = nil, committer: AuthorInfo? = nil) -> Self {
                .init(sha: sha ?? self.sha,
                      message: message ?? self.message,
                      author: self.author?.updated(with: author) ?? author,
                      committer: self.committer?.updated(with: committer) ?? committer)
            }
            
            func updated(with info: Self?) -> Self {
                updated(sha: info?.sha, message: info?.message, author: info?.author, committer: info?.committer)
            }
            
            func extended(sha: String? = nil, message: String? = nil, author: AuthorInfo? = nil, committer: AuthorInfo? = nil) -> Self {
                .init(sha: self.sha ?? sha,
                      message: self.message ?? message,
                      author: self.author?.extended(from: author) ?? author,
                      committer: self.committer?.extended(from: committer) ?? committer)
            }
            
            func extended(from info: Self?) -> Self {
                extended(sha: info?.sha,
                         message: info?.message,
                         author: info?.author,
                         committer: info?.committer)
            }
            
            var debugDescription: String {
                """
                (sha: \(sha ?? ""),
                 message: \(message ?? ""),
                 author: \(author?.debugDescription ?? ""),
                 committer: \(committer?.debugDescription ?? ""))
                """
            }
            
            static func maybe(sha: String? = nil, message: String? = nil, author: AuthorInfo? = nil, committer: AuthorInfo? = nil) -> Self? {
                guard sha != nil || message != nil || author != nil || committer != nil else {
                    return nil
                }
                return .init(sha: sha, message: message, author: author, committer: committer)
            }
        }
        
        struct BaseBranchInfo: CustomDebugStringConvertible {
            let name: String?
            let sha: String?
            let headSha: String?
            
            init(name: String? = nil, sha: String? = nil, headSha: String? = nil) {
                self.name = name
                self.sha = sha
                self.headSha = headSha
            }
            
            func updated(name: String? = nil, sha: String? = nil, headSha: String? = nil) -> Self {
                .init(name: name ?? self.name, sha: sha ?? self.sha, headSha: headSha ?? self.headSha)
            }
            
            func updated(with info: Self?) -> Self {
                updated(name: info?.name, sha: info?.sha, headSha: info?.headSha)
            }
            
            var debugDescription: String {
                "(name: \(name ?? ""), sha: \(sha ?? ""), headSha: \(headSha ?? ""))"
            }
            
            static func maybe(name: String? = nil, sha: String? = nil, headSha: String? = nil) -> Self? {
                guard sha != nil || name != nil || headSha != nil else {
                    return nil
                }
                return .init(name: name, sha: sha, headSha: headSha)
            }
        }
        
        // git.*
        let repositoryURL: URL?
        let branch: String?
        let tag: String?
        
        // git.commit.*
        let commit: CommitInfo?
        
        // git.commit.head.*
        let commitHead: CommitInfo?
        
        // git.pull_request.*
        let pullRequestBaseBranch: BaseBranchInfo?
        
        var repositoryName: String? {
            repositoryURL?.deletingPathExtension().lastPathComponent
        }
        
        init(repositoryURL: URL? = nil, branch: String? = nil, tag: String? = nil,
             commit: CommitInfo? = nil, commitHead: CommitInfo? = nil,
             pullRequestBaseBranch: BaseBranchInfo? = nil)
        {
            self.repositoryURL = repositoryURL
            self.branch = branch
            self.tag = tag
            self.commit = commit
            self.commitHead = commitHead
            self.pullRequestBaseBranch = pullRequestBaseBranch
        }
        
        func extended(from info: GitInfo) -> Git {
            let (_branch, isTag) = Self.normalize(branchOrTag: info.branch)
            let infoCommit = CommitInfo(
                sha: info.commit,
                message: info.commitMessage,
                author: .maybe(name: info.authorName, email: info.authorEmail, date: info.authorDate),
                committer: .maybe(name: info.committerName, email: info.committerEmail, date: info.committerDate)
            )
            return Git(
                repositoryURL: repositoryURL ?? info.repository.flatMap { URL(string: $0) },
                branch: branch ?? (isTag ? nil : _branch),
                tag: tag ?? (isTag ? branch : nil),
                commit: commit?.extended(from: infoCommit) ?? infoCommit,
                commitHead: commitHead,
                pullRequestBaseBranch: pullRequestBaseBranch
            )
        }
        
        func updated(with info: Git) -> Git {
            Git(
                repositoryURL: info.repositoryURL ?? repositoryURL,
                branch: info.branch ?? branch,
                tag: info.tag ?? tag,
                commit: commit?.updated(with: info.commit) ?? info.commit,
                commitHead: commitHead?.updated(with: info.commitHead) ?? info.commitHead,
                pullRequestBaseBranch: pullRequestBaseBranch?.updated(with: info.pullRequestBaseBranch) ?? info.pullRequestBaseBranch
            )
        }
        
        static func normalize(branchOrTag value: String?) -> (String?, Bool) {
            guard var result = value else { return (nil, false) }
            let isTag = result.contains("/tags/") || result.hasPrefix("tags/") || result.contains("/tag/") || result.hasPrefix("tag/")
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
              Commit: \(commit?.debugDescription ?? "")
              CommitHead: \(commitHead?.debugDescription ?? "")
              Pull Request Base Branch: \(pullRequestBaseBranch?.debugDescription ?? "")
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
