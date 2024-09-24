/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct CircleCIEnvironmentReader: CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool { env["CIRCLECI"] ?? "" != "" }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        let pipelineId = env["CIRCLE_WORKFLOW_ID", String.self]
        
        var environment = [String: SpanAttributeConvertible]()
        environment["CIRCLE_WORKFLOW_ID"] = pipelineId
        environment["CIRCLE_BUILD_NUM"] = env["CIRCLE_BUILD_NUM", String.self]
        
        return (
            ci: .init(
                provider: "circleci",
                pipelineId: pipelineId,
                pipelineName: env["CIRCLE_PROJECT_REPONAME"],
                pipelineURL: pipelineId.flatMap { URL(string: "https://app.circleci.com/pipelines/workflows/\($0)") },
                jobName: env["CIRCLE_JOB"],
                jobURL: env["CIRCLE_BUILD_URL"],
                workspacePath: expand(path: env["CIRCLE_WORKING_DIRECTORY"], env: env),
                environment: environment
            ),
            git: .init(
                repositoryURL: env["CIRCLE_REPOSITORY_URL"],
                branch: normalize(branch: env["CIRCLE_BRANCH"]),
                tag: normalize(tag: env["CIRCLE_TAG"]),
                commitSHA: env["CIRCLE_SHA1"]
            )
        )
    }
}
