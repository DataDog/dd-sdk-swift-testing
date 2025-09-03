/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct DroneCIEnvironmentReader: CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool { env["DRONE"] ?? "" != "" }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        let workspacePath = expand(path: env["DRONE_WORKSPACE"], env: env)
        // Pull request support
        let pullRequestNumber: String?
        if let intPr = env["DRONE_PULL_REQUEST", Int.self] {
            pullRequestNumber = String(intPr)
        } else {
            pullRequestNumber = env["DRONE_PULL_REQUEST"]
        }
        let pullRequestBaseBranch = env["DRONE_TARGET_BRANCH", String.self]
        
        return (
            ci: .init(
                provider: "drone",
                pipelineNumber: env["DRONE_BUILD_NUMBER"],
                pipelineURL: env["DRONE_BUILD_LINK"],
                stageName: env["DRONE_STAGE_NAME"],
                jobName: env["DRONE_STEP_NAME"],
                jobURL: env["DRONE_BUILD_LINK"],
                workspacePath: workspacePath,
                prNumber: pullRequestNumber,
                environment: [:]
            ),
            git: .init(
                repositoryURL: env["DRONE_GIT_HTTP_URL"],
                branch: normalize(branch: env["DRONE_BRANCH"]),
                tag: normalize(branchOrTag: env["DRONE_TAG"]).0,
                commitSHA: env["DRONE_COMMIT_SHA"],
                commitMessage: env["DRONE_COMMIT_MESSAGE"],
                authorName: env["DRONE_COMMIT_AUTHOR_NAME"],
                authorEmail: env["DRONE_COMMIT_AUTHOR_EMAIL"],
                pullRequestBaseBranch: normalize(branch: pullRequestBaseBranch)
            )
        )
    }
}
