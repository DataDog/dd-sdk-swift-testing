/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct AwsCodeBuildCIEnvironmentReader: CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool { env["CODEBUILD_BUILD_ID"] ?? "" != "" }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        let idAndName = (env["CODEBUILD_BUILD_ID"] ?? "").components(separatedBy: ":")
        let (id, name) = idAndName.count > 1 ? (idAndName[1], idAndName[0]) : (idAndName[0], nil)
        
        return (
            ci: .init(
                provider: "awscodebuild",
                pipelineId: id,
                pipelineName: name,
                pipelineNumber: env["CODEBUILD_BUILD_NUMBER"],
                pipelineURL: env["CODEBUILD_BUILD_URL"],
                workspacePath: expand(path: env["CODEBUILD_SRC_DIR"], env: env)
            ),
            git: .init(
                repositoryURL: env["CODEBUILD_SOURCE_REPO_URL"],
                commitSHA: env["CODEBUILD_RESOLVED_SOURCE_VERSION"]
            )
        )
    }
}
