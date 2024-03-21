/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct BitriseCIEnvironmentReader: CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool { env.has(env: "BITRISE_BUILD_SLUG") }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        let commitMessage: String? = env["BITRISE_GIT_MESSAGE"] ?? env["GIT_CLONE_COMMIT_MESSAGE_SUBJECT"].flatMap({
            $0 + (env["GIT_CLONE_COMMIT_MESSAGE_BODY"].map({ ":\n" + $0 }) ?? "")
        }) ?? env["GIT_CLONE_COMMIT_MESSAGE_BODY"]
        
        return (
            ci: .init(
                provider: "bitrise",
                pipelineId: env["BITRISE_BUILD_SLUG"],
                pipelineName: env["BITRISE_TRIGGERED_WORKFLOW_ID"] ?? env["BITRISE_APP_TITLE"],
                pipelineNumber: env["BITRISE_BUILD_NUMBER"],
                pipelineURL: env["BITRISE_BUILD_URL"],
                workspacePath: expand(path: env["BITRISE_SOURCE_DIR"], env: env)
            ),
            git: .init(
                repositoryURL: env["GIT_REPOSITORY_URL"],
                branch: normalize(branch: env["BITRISE_GIT_BRANCH"]),
                tag: normalize(tag: env["BITRISE_GIT_TAG"]),
                commitSHA: env["BITRISE_GIT_COMMIT"] ?? env["GIT_CLONE_COMMIT_HASH"],
                commitMessage: commitMessage,
                authorName: env["GIT_CLONE_COMMIT_AUTHOR_NAME"],
                authorEmail: env["GIT_CLONE_COMMIT_AUTHOR_EMAIL"],
                committerName: env["GIT_CLONE_COMMIT_COMMITER_NAME"],
                committerEmail: env["GIT_CLONE_COMMIT_COMMITER_EMAIL"]
            )
        )
    }
}
