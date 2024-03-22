/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct GithubCIEnvironmentReader: CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool {
        env.has(env: "GITHUB_ACTIONS") || env.has(env: "GITHUB_ACTION")
    }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        let repositoryEnv = env["GITHUB_REPOSITORY"] ?? ""
        let githubServerEnv = env["GITHUB_SERVER_URL"] ?? "https://github.com"
        let envRunId = env["GITHUB_RUN_ID", String.self]
        let commit = env["GITHUB_SHA", String.self]
        let attempts = env["GITHUB_RUN_ATTEMPT", String.self].map { "/attempts/" + $0 } ?? ""
        let branch: String? = env["GITHUB_HEAD_REF"] ?? env["GITHUB_REF"]
        
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
                commitSHA: commit
            )
        )
    }
}
