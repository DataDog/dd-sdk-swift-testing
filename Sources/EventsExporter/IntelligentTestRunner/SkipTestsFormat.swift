/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

struct SkipTestsRequestFormat: Codable, JSONable {
    var data: SkipTestsRequestData

    struct SkipTestRequestAttributes: Codable {
        var env: String
        var service: String
        var repository_url: String
        var sha: String
        var configurations: [String: JSONGeneric]
    }

    struct SkipTestsRequestData: Codable {
        var type = "test_params"
        var attributes: SkipTestRequestAttributes

        init(env: String, service: String, repositoryURL: String, sha: String, configurations: [String: JSONGeneric]) {
            self.attributes = SkipTestRequestAttributes(env: env, service: service, repository_url: repositoryURL, sha: sha, configurations: configurations)
        }
    }

    init(env: String, service: String, repositoryURL: String, sha: String, configurations: [String: JSONGeneric]) {
        self.data = SkipTestsRequestData(env: env, service: service, repositoryURL: repositoryURL, sha: sha, configurations: configurations)
    }
}

struct SkipTestsResponseFormat: Decodable {
    var data: [SkipTestsResponseData]

    struct SkipTestResponseAttributes: Decodable {
        var name: String
        var parameters: String?
        var suite: String
        var configuration: [String: JSONGeneric]?
    }

    struct SkipTestsResponseData: Decodable {
        var type = "test"
        var id: String
        var attributes: SkipTestResponseAttributes
    }
}

public struct SkipTestPublicFormat: CustomStringConvertible {
    public var name: String
    public var suite: String
    public var configuration: [String: String]?
    public var customConfiguration: [String: String]?

    public var description: String {
        return "{name:\(name), suite:\(suite), configuration: \(configuration ?? [:]), customConfiguration: \(customConfiguration ?? [:])}"
    }
}
