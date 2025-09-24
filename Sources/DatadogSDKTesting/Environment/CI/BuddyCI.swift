/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct BuddyCIEnvironmentReader: CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool { env["BUDDY"] ?? "" != "" }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        let pipelineId: String? = env["BUDDY_PIPELINE_ID"].flatMap { pId in
            env["BUDDY_EXECUTION_ID"].map { pId + "/" + $0 }
        }
        return (
            ci: .init(
                provider: "buddy",
                pipelineId: pipelineId,
                pipelineName: env["BUDDY_PIPELINE_NAME"],
                pipelineNumber: env["BUDDY_EXECUTION_ID"],
                pipelineURL: env["BUDDY_EXECUTION_URL"],
                workspacePath: expand(path: env["CI_WORKSPACE_PATH"], env: env),
                prNumber: env["BUDDY_RUN_PR_NO"]
            ),
            git: .init(
                repositoryURL: env["BUDDY_SCM_URL"],
                branch: normalize(branch: env["BUDDY_EXECUTION_BRANCH"]),
                tag: normalize(branchOrTag: env["BUDDY_EXECUTION_TAG"]).0,
                commit: .maybe(sha: env["BUDDY_EXECUTION_REVISION"],
                               message: env["BUDDY_EXECUTION_REVISION_MESSAGE"],
                               committer: .maybe(name: env["BUDDY_EXECUTION_REVISION_COMMITTER_NAME"],
                                                 email: env["BUDDY_EXECUTION_REVISION_COMMITTER_EMAIL"])),
                pullRequestBaseBranch: .maybe(name: env["BUDDY_RUN_PR_BASE_BRANCH"])
            )
        )
    }
}
