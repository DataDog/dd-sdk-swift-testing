/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct AzureCIEnvironmentReader: CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool { env.has(env: "TF_BUILD") }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        let pipelineId = env["BUILD_BUILDID", String.self]
        let foundationServerUri = env["SYSTEM_TEAMFOUNDATIONSERVERURI"] ?? ""
        let teamProjectId = env["SYSTEM_TEAMPROJECTID"] ?? ""
        let pipelineURL = "\(foundationServerUri)\(teamProjectId)/_build/results?buildId=\(pipelineId ?? "")"
        
        let jobId = env["SYSTEM_JOBID"] ?? ""
        let taskId = env["SYSTEM_TASKINSTANCEID"] ?? ""
        let branch: String? = env["SYSTEM_PULLREQUEST_SOURCEBRANCH"] ?? env["BUILD_SOURCEBRANCH"]
   
        var environment = [String: SpanAttributeConvertible]()
        environment["SYSTEM_TEAMPROJECTID"] = env["SYSTEM_TEAMPROJECTID", String.self]
        environment["BUILD_BUILDID"] = env["BUILD_BUILDID", String.self]
        environment["SYSTEM_JOBID"] = env["SYSTEM_JOBID", String.self]
        
        return (
            ci: .init(
                provider: "azurepipelines",
                pipelineId: pipelineId,
                pipelineName: env["BUILD_DEFINITIONNAME"],
                pipelineNumber: env["BUILD_BUILDID"],
                pipelineURL: URL(string: pipelineURL),
                stageName: env["SYSTEM_STAGEDISPLAYNAME"],
                jobName: env["SYSTEM_JOBDISPLAYNAME"],
                jobURL: URL(string: pipelineURL + "&view=logs&j=\(jobId)&t=\(taskId)"),
                workspacePath: expand(path: env["BUILD_SOURCESDIRECTORY"], env: env),
                environment: environment
            ),
            git: .init(
                repositoryURL: env["SYSTEM_PULLREQUEST_SOURCEREPOSITORYURI"] ?? env["BUILD_REPOSITORY_URI"],
                branch: normalize(branch: branch),
                tag: normalize(tag: branch),
                commitSHA: env["SYSTEM_PULLREQUEST_SOURCECOMMITID"] ?? env["BUILD_SOURCEVERSION"],
                commitMessage: env["BUILD_SOURCEVERSIONMESSAGE"],
                authorName: env["BUILD_REQUESTEDFORID"],
                authorEmail: env["BUILD_REQUESTEDFOREMAIL"]
            )
        )
    }
}
