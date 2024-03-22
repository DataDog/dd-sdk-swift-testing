/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct BitbucketCIEnvironmentReader: CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool { env.has(env: "BITBUCKET_COMMIT") }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        let pipelineId = env["BITBUCKET_PIPELINE_UUID", String.self]
        let pipelineNumber = env["BITBUCKET_BUILD_NUMBER", String.self]
        let pipelineName = env["BITBUCKET_REPO_FULL_NAME", String.self]
        let pipelineURL = "https://bitbucket.org/\(pipelineName ?? "")/addon/pipelines/home#!/results/\(pipelineNumber ?? "")"
        
        return (
            ci: .init(
                provider: "bitbucket",
                pipelineId: pipelineId?.replacingOccurrences(of: "[{}]", with: "", options: .regularExpression),
                pipelineName: pipelineName,
                pipelineNumber: pipelineNumber,
                pipelineURL: URL(string: pipelineURL),
                jobURL: URL(string: pipelineURL),
                workspacePath: expand(path: env["BITBUCKET_CLONE_DIR"], env: env)
            ),
            git: .init(
                repositoryURL: env["BITBUCKET_GIT_SSH_ORIGIN"] ?? env["BITBUCKET_GIT_HTTP_ORIGIN"],
                branch: normalize(branch: env["BITBUCKET_BRANCH"]),
                tag: normalize(tag: env["BITBUCKET_TAG"]),
                commitSHA: env["BITBUCKET_COMMIT"]
            )
        )
    }
}
