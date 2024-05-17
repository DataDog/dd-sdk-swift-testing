/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

struct SkipTestsRequestFormat: Codable, JSONable {
    let data: SkipTestsRequestData

    struct SkipTestRequestAttributes: Codable {
        let env: String
        let service: String
        let repositoryUrl: String
        let sha: String
        let configurations: [String: JSONGeneric]
        let testLevel: ITRTestLevel
        
        enum CodingKeys: String, CodingKey {
            case env
            case service
            case repositoryUrl = "repository_url"
            case sha
            case configurations
            case testLevel = "test_level"
        }
    }

    struct SkipTestsRequestData: Codable {
        var type: String = "test_params"
        let attributes: SkipTestRequestAttributes

        init(env: String, service: String, repositoryURL: String, sha: String, testLevel: ITRTestLevel, configurations: [String: JSONGeneric]) {
            self.attributes = SkipTestRequestAttributes(env: env, service: service, repositoryUrl: repositoryURL,
                                                        sha: sha, configurations: configurations, testLevel: testLevel)
        }
    }

    init(env: String, service: String, repositoryURL: String, sha: String, testLevel: ITRTestLevel, configurations: [String: JSONGeneric]) {
        self.data = SkipTestsRequestData(env: env, service: service, repositoryURL: repositoryURL,
                                         sha: sha, testLevel: testLevel, configurations: configurations)
    }
}

struct SkipTestsResponseFormat: Decodable {
    let meta: Meta
    let data: [SkipTestsResponseData]
    
    struct Meta: Decodable {
        let correlationId: String
        
        enum CodingKeys: String, CodingKey {
            case correlationId = "correlation_id"
        }
    }

    struct SkipTestResponseAttributes: Decodable {
        let name: String
        let parameters: String?
        let suite: String
        let configuration: [String: JSONGeneric]?
    }

    struct SkipTestsResponseData: Decodable {
        var type: String = "test"
        let id: String
        let attributes: SkipTestResponseAttributes
    }
}

public struct SkipTestPublicFormat: CustomStringConvertible, Codable {
    public var name: String
    public var suite: String
    public var configuration: [String: String]?
    public var customConfiguration: [String: String]?

    public var description: String {
        return "{name:\(name), suite:\(suite), configuration: \(configuration ?? [:]), customConfiguration: \(customConfiguration ?? [:])}"
    }
}

public struct SkipTests: Codable {
    public let correlationId: String
    public let tests: [SkipTestPublicFormat]
}
