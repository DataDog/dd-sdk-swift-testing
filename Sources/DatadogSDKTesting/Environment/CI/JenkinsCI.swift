/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct JenkinsCIEnvironmentReader: CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool { env["JENKINS_URL"] ?? "" != "" }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        let (branch, isTag) = normalize(branchOrTag: env["GIT_BRANCH"])
        
        var environment = [String: SpanAttributeConvertible]()
        environment["DD_CUSTOM_TRACE_ID"] = env["DD_CUSTOM_TRACE_ID", String.self]
        
        return (
            ci: .init(
                provider: "jenkins",
                pipelineId: env["BUILD_TAG"],
                pipelineName: filterJobName(name: env["JOB_NAME"], gitBranch: branch),
                pipelineNumber: env["BUILD_NUMBER"],
                pipelineURL: env["BUILD_URL"],
                workspacePath: expand(path: env["WORKSPACE"], env: env),
                nodeName: env["NODE_NAME"],
                nodeLabels: env["NODE_LABELS"],
                environment: environment
            ),
            git: .init(
                repositoryURL: env["GIT_URL"] ?? env["GIT_URL_1"],
                branch: isTag ? nil : branch,
                tag: isTag ? branch : nil,
                commitSHA: env["GIT_COMMIT"]
            )
        )
    }
    
    private func filterJobName(name: String?, gitBranch: String?) -> String? {
        guard let name = name else { return nil }
        
        let jobNameNoBranch = gitBranch.map {
            name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/" + $0, with: "")
        } ?? name

        var configurations = [String: String]()
        let jobNameParts = jobNameNoBranch.split(separator: "/")
        if jobNameParts.count > 1, jobNameParts[1].contains("=") {
            let configStr = jobNameParts[1].lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let configsKeyValue = configStr.split(separator: ",")
            configsKeyValue.forEach {
                let keyValue = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: "=")
                configurations[String(keyValue[0])] = String(keyValue[1])
            }
        }

        if configurations.isEmpty {
            return jobNameNoBranch
        } else {
            return String(jobNameParts[0])
        }
    }
}
