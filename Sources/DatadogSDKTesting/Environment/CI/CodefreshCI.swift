/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct CodefreshCIEnvironmentReader: CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool { env.has(env: "CF_BUILD_ID") }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        var environment = [String: SpanAttributeConvertible]()
        environment["CF_BUILD_ID"] = env["CF_BUILD_ID", String.self]
        
        return (
            ci: .init(
                provider: "codefresh",
                pipelineId: env["CF_BUILD_ID"],
                pipelineName: env["CF_PIPELINE_NAME"],
                pipelineURL: env["CF_BUILD_URL"],
                jobName: env["CF_STEP_NAME"],
                environment: environment
            ),
            git: .init(
                branch: normalize(branch: env["CF_BRANCH"]),
                tag: normalize(tag: env["CF_BRANCH"])
            )
        )
    }
}
