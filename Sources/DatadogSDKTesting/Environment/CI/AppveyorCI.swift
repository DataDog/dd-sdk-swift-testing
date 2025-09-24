/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct AppveyorCIEnvironmentReader: CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool { env["APPVEYOR"] ?? "" != "" }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        let pipelineId = env["APPVEYOR_BUILD_ID", String.self]
        let repoName = env["APPVEYOR_REPO_NAME"] ?? ""
        let pipelineURL = URL(string: "https://ci.appveyor.com/project/\(repoName)/builds/\(pipelineId ?? "")")
        
        let prBranch: String?, branch: String?
        if let prBranchEnv: String = env["APPVEYOR_PULL_REQUEST_HEAD_REPO_BRANCH"] {
            branch = normalize(branch: prBranchEnv)
            prBranch = normalize(branch: env["APPVEYOR_REPO_BRANCH"])
        } else {
            prBranch = nil
            branch = normalize(branch: env["APPVEYOR_REPO_BRANCH"])
        }
        
        return (
            ci: .init(
                provider: "appveyor",
                pipelineId: pipelineId,
                pipelineName: env["APPVEYOR_REPO_NAME"],
                pipelineNumber: env["APPVEYOR_BUILD_NUMBER"],
                pipelineURL: pipelineURL,
                jobURL: pipelineURL,
                workspacePath: expand(path: env["APPVEYOR_BUILD_FOLDER"], env: env),
                prNumber: env["APPVEYOR_PULL_REQUEST_NUMBER"]
            ),
            git: .init(
                repositoryURL: URL(string: "https://github.com/\(repoName).git"),
                branch: branch,
                tag: normalize(tag: env["APPVEYOR_REPO_TAG_NAME"]),
                commit: .maybe(sha: env["APPVEYOR_REPO_COMMIT"],
                               message: env["APPVEYOR_REPO_COMMIT_MESSAGE"].map { message in
                                   env["APPVEYOR_REPO_COMMIT_MESSAGE_EXTENDED"].map { message + "\n" + $0 } ?? message
                               },
                               author: .maybe(name: env["APPVEYOR_REPO_COMMIT_AUTHOR"],
                                              email: env["APPVEYOR_REPO_COMMIT_AUTHOR_EMAIL"])),
                commitHead: .maybe(sha: env["APPVEYOR_PULL_REQUEST_HEAD_COMMIT"]),
                pullRequestBaseBranch: .maybe(name: prBranch)
            )
        )
    }
}
