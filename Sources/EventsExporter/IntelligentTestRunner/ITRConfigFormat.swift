/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

struct ITRConfigResponseFormat: Codable, JSONable {
    let data: SkipTestsResponseData

    struct SkipTestsResponseData: Codable {
        let attributes: Attributes
        var id = "1"
        var type = "ci_app_tracers_test_service_settings"

        struct Attributes: Codable {
            let codeCoverage: Bool
            let testsSkipping: Bool
            let requireGit: Bool
            
            enum CodingKeys: String, CodingKey {
                case codeCoverage = "code_coverage"
                case testsSkipping = "tests_skipping"
                case requireGit = "require_git"
            }
        }
    }
}

struct ITRConfigRequesFormat: Codable, JSONable {
    let data: ITRConfigRequestData

    struct ITRConfigRequestData: Codable {
        var id = "1"
        var type = "ci_app_test_service_libraries_settings"
        let attributes: Attributes
        
        struct Attributes: Codable {
            let service: String
            let env: String
            let repositoryURL: String
            let branch: String
            let sha: String
            let configurations: [String: JSONGeneric]
            let testLevel: ITRTestLevel

            enum CodingKeys: String, CodingKey {
                case service
                case env
                case repositoryURL = "repository_url"
                case branch
                case sha
                case configurations
                case testLevel = "test_level"
            }
        }
    }

    internal init(
        service: String, env: String, repositoryURL: String, branch: String,
        sha: String, configurations: [String: JSONGeneric], testLevel: ITRTestLevel
    ) {
        self.data = ITRConfigRequestData(
            attributes: ITRConfigRequestData.Attributes(
                service: service, env: env, repositoryURL: repositoryURL, branch: branch, sha: sha,
                configurations: configurations, testLevel: testLevel
            )
        )
    }
}

public enum ITRTestLevel: String, Codable {
    case test
    case suite
}

public struct ITRSettings {
    public let codeCoverage: Bool
    public let testsSkipping: Bool
    public let requireGit: Bool
    
    init(attrs: ITRConfigResponseFormat.SkipTestsResponseData.Attributes) {
        codeCoverage = attrs.codeCoverage
        testsSkipping = attrs.testsSkipping
        requireGit = attrs.requireGit
    }
}
