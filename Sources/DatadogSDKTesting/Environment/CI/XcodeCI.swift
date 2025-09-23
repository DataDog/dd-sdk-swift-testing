/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct XcodeCIEnvironmentReader: CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool { env["CI_WORKSPACE"] ?? "" != "" }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        return (
            ci: .init(
                provider: "xcodecloud",
                pipelineId: env["CI_BUILD_ID"],
                pipelineName: env["CI_WORKFLOW"],
                pipelineNumber: env["CI_BUILD_NUMBER"],
                workspacePath: expand(path: env["CI_WORKSPACE"], env: env)
            ),
            git: .init(
                branch: normalize(branch: env["CI_BRANCH"] ?? env["CI_GIT_REF"]),
                tag: normalize(tag: env["CI_TAG"] ?? env["CI_GIT_REF"]),
                commit: .maybe(sha: env["CI_COMMIT"])
            )
        )
    }
}
