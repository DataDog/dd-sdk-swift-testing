/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct AwsCodePipelineCIEnvironmentReader: CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool {
        env["CODEBUILD_INITIATOR", String.self]?.hasPrefix("codepipeline") ?? false
    }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        var environment = [String: SpanAttributeConvertible]()
        environment["CODEBUILD_BUILD_ARN"] = env["CODEBUILD_BUILD_ARN", String.self]
        environment["DD_PIPELINE_EXECUTION_ID"] = env["DD_PIPELINE_EXECUTION_ID", String.self]
        environment["DD_ACTION_EXECUTION_ID"] = env["DD_ACTION_EXECUTION_ID", String.self]
        
        return (
            ci: .init(
                provider: "awscodepipeline",
                pipelineId: env["DD_PIPELINE_EXECUTION_ID"],
                jobId: env["DD_ACTION_EXECUTION_ID"],
                environment: environment
            ),
            git: .init()
        )
    }
}
