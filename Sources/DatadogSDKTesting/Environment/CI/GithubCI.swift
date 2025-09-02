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
        let baseBranch = env["GITHUB_BASE_REF"]
        let (prHeadSha, prBaseSha) = parsePullRequestEvent(env: env, base: baseBranch)
        
        var environment = [String: SpanAttributeConvertible]()
        environment["GITHUB_REPOSITORY"] = env["GITHUB_REPOSITORY", String.self]
        environment["GITHUB_SERVER_URL"] = env["GITHUB_SERVER_URL", URL.self]
        environment["GITHUB_RUN_ID"] = env["GITHUB_RUN_ID", String.self]
        environment["GITHUB_RUN_ATTEMPT"] = env["GITHUB_RUN_ATTEMPT", String.self]
        
        return (
            ci: .init(
                provider: "github",
                pipelineId: envRunId,
                pipelineName: env["GITHUB_WORKFLOW"],
                pipelineNumber: env["GITHUB_RUN_NUMBER"],
                pipelineURL: URL(string: "\(githubServerEnv)/\(repositoryEnv)/actions/runs/\(envRunId ?? "")" + attempts),
                jobName: env["GITHUB_JOB"],
                jobURL: URL(string: "\(githubServerEnv)/\(repositoryEnv)/commit/\(commit ?? "")/checks"),
                workspacePath: expand(path: env["GITHUB_WORKSPACE"], env: env),
                environment: environment
            ),
            git: .init(
                repositoryURL: URL(string: "\(githubServerEnv)/\(repositoryEnv).git"),
                branch: normalize(branch: branch),
                tag: normalize(tag: branch),
                commitSHA: commit,
                pullRequestHeadSha: prHeadSha,
                pullRequestBaseBranch: baseBranch,
                pullRequestBaseBranchSha: prBaseSha
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
        guard let eventPath = env["GITHUB_EVENT_PATH"] else {
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
}
