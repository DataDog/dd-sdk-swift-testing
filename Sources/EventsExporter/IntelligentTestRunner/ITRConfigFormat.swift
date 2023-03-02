/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

struct ITRConfigResponseFormat: Codable, JSONable {
    var data: SkipTestsResponseData

    struct SkipTestsResponseData: Codable {
        var attributes: Attributes
        var id = "1"
        var type = "ci_app_tracers_test_service_settings"

        struct Attributes: Codable {
            var code_coverage: Bool
            var tests_skipping: Bool
        }
    }
}

struct ITRConfigRequesFormat: Codable, JSONable {
    var data: ITRConfigRequestData

    struct ITRConfigRequestData: Codable {
        var id = "1"
        var type = "ci_app_test_service_libraries_settings"
        var attributes: Attributes

        struct Attributes: Codable {
            var service: String
            var env: String
            var repositoryURL: String
            var branch: String
            var sha: String
            var configurations: [String: JSONGeneric]

            enum CodingKeys: String, CodingKey {
                case service
                case env
                case repositoryURL = "repository_url"
                case branch
                case sha
                case configurations
            }
        }
    }

    internal init(service: String, env: String, repositoryURL: String, branch: String, sha: String, configurations: [String: JSONGeneric]) {
        self.data = ITRConfigRequestData(attributes: ITRConfigRequestData.Attributes(service: service, env: env, repositoryURL: repositoryURL, branch: branch, sha: sha, configurations: configurations))
    }
}
