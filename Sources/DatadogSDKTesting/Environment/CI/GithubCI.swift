/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

// GitHub Event JSON structures for pull request data
private struct GitHubEvent: Decodable {
    let pull_request: PullRequest?
    
    struct PullRequest: Decodable {
        let head: Ref
        let base: Ref
        
        struct Ref: Decodable {
            let sha: String
        }
    }
}

internal struct GithubCIEnvironmentReader: CIEnvironmentReader {
    private let _diagnosticDirs: [URL]
    
    init(diagnosticDirs: [URL] = [
        URL(fileURLWithPath: "/home/runner/actions-runner/cached/_diag", isDirectory: true), // for SaaS
        URL(fileURLWithPath: "/home/runner/actions-runner/_diag", isDirectory: true), // for self-hosted
    ]) {
        self._diagnosticDirs = diagnosticDirs
    }
    
    func isActive(env: any EnvironmentReader) -> Bool {
        env["GITHUB_ACTIONS"] ?? env["GITHUB_ACTION"] ?? "" != ""
    }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        let repositoryEnv = env["GITHUB_REPOSITORY"] ?? ""
        let githubServerEnv = env["GITHUB_SERVER_URL"] ?? "https://github.com"
        let envRunId = env["GITHUB_RUN_ID", String.self]
        let commit = env["GITHUB_SHA", String.self]
        let attempts = env["GITHUB_RUN_ATTEMPT", String.self].map { "/attempts/" + $0 } ?? ""
        let branch: String? = env["GITHUB_HEAD_REF"] ?? env["GITHUB_REF"]
        
        // Check if we're in a pull request event and extract PR metadata
        let baseBranch: String? = env["GITHUB_BASE_REF"]
        let (prHeadSha, prBaseSha) = parsePullRequestEvent(env: env, base: baseBranch)
        
        var environment = [String: SpanAttributeConvertible]()
        environment["GITHUB_REPOSITORY"] = env["GITHUB_REPOSITORY", String.self]
        environment["GITHUB_SERVER_URL"] = env["GITHUB_SERVER_URL", URL.self]
        environment["GITHUB_RUN_ID"] = env["GITHUB_RUN_ID", String.self]
        environment["GITHUB_RUN_ATTEMPT"] = env["GITHUB_RUN_ATTEMPT", String.self]
        
        let jobId = getJobId(env: env)
        
        let jobUrl = envRunId.flatMap { runId in
            jobId.map { (runId, $0) }
        }.flatMap { (runId, jobId) in
            URL(string: "\(githubServerEnv)/\(repositoryEnv)/actions/runs/\(runId)/job/\(jobId)")
        } ?? URL(string: "\(githubServerEnv)/\(repositoryEnv)/commit/\(commit ?? "")/checks")
        
        return (
            ci: .init(
                provider: "github",
                pipelineId: envRunId,
                pipelineName: env["GITHUB_WORKFLOW"],
                pipelineNumber: env["GITHUB_RUN_NUMBER"],
                pipelineURL: URL(string: "\(githubServerEnv)/\(repositoryEnv)/actions/runs/\(envRunId ?? "")" + attempts),
                jobId: jobId ?? env["GITHUB_JOB"],
                jobName: env["GITHUB_JOB"],
                jobURL: jobUrl,
                workspacePath: expand(path: env["GITHUB_WORKSPACE"], env: env),
                environment: environment
            ),
            git: .init(
                repositoryURL: URL(string: "\(githubServerEnv)/\(repositoryEnv).git"),
                branch: normalize(branch: branch),
                tag: normalize(tag: branch),
                commit: .maybe(sha: commit),
                commitHead: .maybe(sha: prHeadSha),
                pullRequestBaseBranch: .maybe(name: baseBranch, sha: prBaseSha)
            )
        )
    }
    
    /// Parse GitHub event file to extract pull request metadata
    private func parsePullRequestEvent(env: any EnvironmentReader, base: String?) -> (headSha: String?, baseSha: String?) {
        // Only parse if GITHUB_BASE_REF is present (indicates pull request)
        guard base != nil else {
            return (nil, nil)
        }
        
        // Get the path to the GitHub event file
        guard let eventPath: String = env["GITHUB_EVENT_PATH"] else {
            return (nil, nil)
        }
        
        // Read and parse the event file
        guard let eventData = try? Data(contentsOf: URL(fileURLWithPath: eventPath)),
              let githubEvent = try? JSONDecoder().decode(GitHubEvent.self, from: eventData),
              let pullRequest = githubEvent.pull_request else {
            return (nil, nil)
        }
        
        return (pullRequest.head.sha, pullRequest.base.sha)
    }
    
    private func getJobId(env: any EnvironmentReader) -> String? {
        if let id: String = env["JOB_CHECK_RUN_ID"] {
            return id
        }
        
        let files: [URL] = _diagnosticDirs.compactMap { dir -> ([URL]?) in
            guard let contents = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                              includingPropertiesForKeys: nil,
                                                                              options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
            else {
                return nil
            }
            return contents.filter { $0.pathExtension == "log" && $0.lastPathComponent.hasPrefix("Worker_") }
        }.flatMap { $0 }
        
        let regex = jobIdRegex
        for file in files {
            guard let data = try? String(contentsOf: file) else {
                continue
            }
            if let match = regex.firstMatch(in: data, range: NSRange(location: 0, length: data.utf16.count)) {
                return String(data[Range(match.range(at: 1), in: data)!])
            }
        }
        
        return nil
    }
    
    private var jobIdRegex: NSRegularExpression {
        try! NSRegularExpression(pattern: #""k":\s*"check_run_id"[^}]*"v":\s*(\d+)(?:\.\d+)?"#)
    }
}
