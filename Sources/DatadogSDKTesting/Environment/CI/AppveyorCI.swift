/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct AppveyorCIEnvironmentReader: CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool { env.has(env: "APPVEYOR") }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        let pipelineId = env["APPVEYOR_BUILD_ID", String.self]
        let repoName = env["APPVEYOR_REPO_NAME"] ?? ""
        let pipelineURL = URL(string: "https://ci.appveyor.com/project/\(repoName)/builds/\(pipelineId ?? "")")
        
        return (
            ci: .init(
                provider: "appveyor",
                pipelineId: pipelineId,
                pipelineName: env["APPVEYOR_REPO_NAME"],
                pipelineNumber: env["APPVEYOR_BUILD_NUMBER"],
                pipelineURL: pipelineURL,
                jobURL: pipelineURL,
                workspacePath: expand(path: env["APPVEYOR_BUILD_FOLDER"], env: env)
            ),
            git: .init(
                repositoryURL: URL(string: "https://github.com/\(repoName).git"),
                branch: normalize(branch: env["APPVEYOR_PULL_REQUEST_HEAD_REPO_BRANCH"] ?? env["APPVEYOR_REPO_BRANCH"]),
                tag: normalize(tag: env["APPVEYOR_REPO_TAG_NAME"]),
                commitSHA: env["APPVEYOR_REPO_COMMIT"],
                commitMessage: env["APPVEYOR_REPO_COMMIT_MESSAGE"].map { message in
                    env["APPVEYOR_REPO_COMMIT_MESSAGE_EXTENDED"].map { message + "\n" + $0 } ?? message
                },
                authorName: env["APPVEYOR_REPO_COMMIT_AUTHOR"],
                authorEmail: env["APPVEYOR_REPO_COMMIT_AUTHOR_EMAIL"]
            )
        )
    }
}
