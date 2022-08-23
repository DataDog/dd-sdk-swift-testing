/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

struct SkipTestsRequestFormat: Codable {
    var data: SkipTestsRequestData

    struct SkipTestRequestAttributes: Codable {
        var repository_url: String
        var sha: String
        var configurations: [String: String]
    }

    struct SkipTestsRequestData: Codable {
        var type = "test_params"
        var attributes: SkipTestRequestAttributes

        init(repositoryURL: String, sha: String, configurations: [String: String]) {
            self.attributes = SkipTestRequestAttributes(repository_url: repositoryURL, sha: sha, configurations: configurations)
        }
    }

    init(repositoryURL: String, sha: String, configurations: [String: String]) {
        self.data = SkipTestsRequestData(repositoryURL: repositoryURL, sha: sha, configurations: configurations)
    }
}

extension SkipTestsRequestFormat {
    var jsonData: Data? {
        return try? JSONEncoder().encode(self)
    }

    var json: String? {
        guard let data = self.jsonData else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct SkipTestsResponseFormat: Decodable {
    var data: [SkipTestsResponseData]

    struct SkipTestResponseAttributes: Decodable {
        var name: String
        var parameters: String?
        var suite: String
        var configuration: [String: String]?
    }

    struct SkipTestsResponseData: Decodable {
        var type = "test"
        var id: String
        var attributes: SkipTestResponseAttributes
    }
}

public struct SkipTestPublicFormat {
    public var name: String
    public var suite: String
    public var configuration: [String: String]?
}
