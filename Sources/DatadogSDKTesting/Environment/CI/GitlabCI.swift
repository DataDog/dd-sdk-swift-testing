/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct GitlabCIEnvironmentReader: CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool { env["GITLAB_CI"] ?? "" != "" }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        var authorName: String? = nil
        var authorEmail: String? = nil
        
        if let info = env["CI_COMMIT_AUTHOR", String.self]?.components(separatedBy: CharacterSet(charactersIn: "<>")) {
            if info.count >= 2 {
                authorName = info[0].trimmingCharacters(in: .whitespacesAndNewlines)
                authorEmail = info[1].trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                authorName = info[0].trimmingCharacters(in: .whitespacesAndNewlines)
                authorEmail = nil
            }
        }
        
        let nodeLabels = env["CI_RUNNER_TAGS", String.self].flatMap {
            try? JSONDecoder().decode([String].self, from: Data($0.utf8))
        }

        var environment = [String: SpanAttributeConvertible]()
        environment["CI_PIPELINE_ID"] = env["CI_PIPELINE_ID", String.self]
        environment["CI_JOB_ID"] = env["CI_JOB_ID", String.self]
        environment["CI_PROJECT_URL"] = env["CI_PROJECT_URL", String.self]
        
        return (
            ci: .init(
                provider: "gitlab",
                pipelineId: env["CI_PIPELINE_ID"],
                pipelineName: env["CI_PROJECT_PATH"],
                pipelineNumber: env["CI_PIPELINE_IID"],
                pipelineURL: env["CI_PIPELINE_URL"],
                stageName: env["CI_JOB_STAGE"],
                jobId: env["CI_JOB_ID"],
                jobName: env["CI_JOB_NAME"],
                jobURL: env["CI_JOB_URL"],
                workspacePath: expand(path: env["CI_PROJECT_DIR"], env: env),
                nodeName: env["CI_RUNNER_ID"],
                nodeLabels: nodeLabels,
                prNumber: env["CI_MERGE_REQUEST_IID"],
                environment: environment
            ),
            git: .init(
                repositoryURL: env["CI_REPOSITORY_URL"],
                branch: normalize(branch: env["CI_COMMIT_REF_NAME"] ?? env["CI_COMMIT_BRANCH"]),
                tag: normalize(branchOrTag: env["CI_COMMIT_TAG"]).0,
                commitSHA: env["CI_COMMIT_SHA"],
                commitMessage: env["CI_COMMIT_MESSAGE"],
                authorName: authorName,
                authorEmail: authorEmail,
                authorDate: env["CI_COMMIT_TIMESTAMP"],
                pullRequestBaseBranch: env["CI_MERGE_REQUEST_TARGET_BRANCH_NAME"],
                pullRequestBaseBranchSha: env["CI_MERGE_REQUEST_DIFF_BASE_SHA"],
                pullRequestBaseBranchHeadSha: env["CI_MERGE_REQUEST_TARGET_BRANCH_SHA"]
            )
        )
    }
}
