/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct BuildkiteCIEnvironmentReader: CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool { env["BUILDKITE"] ?? "" != "" }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        let jobId = env["BUILDKITE_JOB_ID", String.self]
        let pipelineURL = env["BUILDKITE_BUILD_URL", String.self]
        let jobURL = (pipelineURL ?? "") + "#" + (jobId ?? "")
        
        let labels: [String] = env.reduce(env: [], prefix: "BUILDKITE_AGENT_META_DATA_") { (res, key, env) in
            let label = key.suffix(from: key.index(key.startIndex, offsetBy: "BUILDKITE_AGENT_META_DATA_".count))
            res.append(label.lowercased() + ":" + (env[key] ?? ""))
        }
        
        var environment = [String: SpanAttributeConvertible]()
        environment["BUILDKITE_BUILD_ID"] = env["BUILDKITE_BUILD_ID", String.self]
        environment["BUILDKITE_JOB_ID"] = jobId
        
        return (
            ci: .init(
                provider: "buildkite",
                pipelineId: env["BUILDKITE_BUILD_ID"],
                pipelineName: env["BUILDKITE_PIPELINE_SLUG"],
                pipelineNumber: env["BUILDKITE_BUILD_NUMBER"],
                pipelineURL: pipelineURL.flatMap { URL(string: $0) },
                jobId: env["BUILDKITE_JOB_ID"],
                jobURL: URL(string: jobURL),
                workspacePath: expand(path: env["BUILDKITE_BUILD_CHECKOUT_PATH"], env: env),
                nodeName: env["BUILDKITE_AGENT_ID"],
                nodeLabels: labels.count > 0 ? labels : nil,
                prNumber: env["BUILDKITE_PULL_REQUEST"],
                environment: environment
            ),
            git: .init(
                repositoryURL: env["BUILDKITE_REPO"],
                branch: normalize(branch: env["BUILDKITE_BRANCH"]),
                tag: normalize(branchOrTag: env["BUILDKITE_TAG"]).0,
                commitSHA: env["BUILDKITE_COMMIT"],
                commitMessage: env["BUILDKITE_MESSAGE"],
                authorName: env["BUILDKITE_BUILD_AUTHOR"],
                authorEmail: env["BUILDKITE_BUILD_AUTHOR_EMAIL"],
                pullRequestBaseBranch: env["BUILDKITE_PULL_REQUEST_BASE_BRANCH"]
            )
        )
    }
}
