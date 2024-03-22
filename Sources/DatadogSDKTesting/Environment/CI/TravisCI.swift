/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct TravisCIEnvironmentReader: CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool { env.has(env: "TRAVIS") }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        let repositoryEnv: String? = env["TRAVIS_PULL_REQUEST_SLUG"] ?? env["TRAVIS_REPO_SLUG"]
        return (
            ci: .init(
                provider: "travisci",
                pipelineId: env["TRAVIS_BUILD_ID"],
                pipelineName: repositoryEnv,
                pipelineNumber: env["TRAVIS_BUILD_NUMBER"],
                pipelineURL: env["TRAVIS_BUILD_WEB_URL"],
                jobURL: env["TRAVIS_JOB_WEB_URL"],
                workspacePath: expand(path: env["TRAVIS_BUILD_DIR"], env: env)
            ),
            git: .init(
                repositoryURL: repositoryEnv.flatMap { URL(string: "https://github.com/\($0).git") },
                branch: normalize(branch: env["TRAVIS_PULL_REQUEST_BRANCH"] ?? env["TRAVIS_BRANCH"]),
                tag: normalize(tag: env["TRAVIS_TAG"]),
                commitSHA: env["TRAVIS_COMMIT"],
                commitMessage: env["TRAVIS_COMMIT_MESSAGE"]
            )
        )
    }
}
