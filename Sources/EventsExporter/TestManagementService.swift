/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal final class TestManagementService {
    let exporterConfiguration: ExporterConfiguration
    let testsUploader: DataUploader
    
    init(config: ExporterConfiguration) throws {
        self.exporterConfiguration = config
        
        let testsRequestBuilder = SingleRequestBuilder(
            url: exporterConfiguration.endpoint.testManagementTestsURL,
            queryItems: [],
            headers: [
                .userAgentHeader(
                    appName: exporterConfiguration.applicationName,
                    appVersion: exporterConfiguration.version,
                    device: Device.current
                ),
                .contentTypeHeader(contentType: .applicationJSON),
                .apiKeyHeader(apiKey: config.apiKey),
                .traceIDHeader(traceID: config.exporterId),
                .parentSpanIDHeader(parentSpanID: config.exporterId),
                .samplingPriorityHeader()
            ]
        )
        
        testsUploader = DataUploader(
            httpClient: HTTPClient(debug: config.debug.logNetworkRequests),
            requestBuilder: testsRequestBuilder
        )
    }
    
    func tests(
        repositoryURL: String, sha: String? = nil, commitMessage: String? = nil, module: String? = nil
    ) -> TestManagementTestsInfo? {
        let testsPayload = TestsRequest(repositoryURL: repositoryURL, sha: sha, commitMessage: commitMessage, module: module)

        guard let jsonData = testsPayload.jsonData,
              let response = testsUploader.uploadWithResponse(data: jsonData)
        else {
            Log.debug("Test Management Tests Request payload: \(testsPayload.jsonString)")
            Log.debug("Test Management Tests Request no response")
            return nil
        }

        guard let settings = try? JSONDecoder().decode(TestsResponse.self, from: response) else {
            Log.debug("Test Management Tests Request invalid response: \(String(decoding: response, as: UTF8.self))")
            return nil
        }
        Log.debug("Test Management Tests Request response: \(String(decoding: response, as: UTF8.self))")

        return TestManagementTestsInfo(modules: settings.data.attributes.modules)
    }
}

extension TestManagementService {
    struct TestsRequest: Codable, JSONable {
        let data: Data
        
        struct Data: Codable {
            var id = "1"
            var type = "ci_app_libraries_tests_request"
            let attributes: Attributes
            
            struct Attributes: Codable {
                let repositoryURL: String
                let commitMessage: String?
                let module: String?
                let sha: String?
                
                enum CodingKeys: String, CodingKey {
                    case repositoryURL = "repository_url"
                    case commitMessage = "commit_message"
                    case module
                    case sha
                }
            }
        }
        
        init(repositoryURL: String, sha: String? = nil, commitMessage: String? = nil, module: String? = nil) {
            self.data = Data(
                attributes: Data.Attributes(
                    repositoryURL: repositoryURL, commitMessage: commitMessage, module: module, sha: sha
                )
            )
        }
    }
    
    struct TestsResponse: Codable {
        let data: Data
        
        struct Data: Codable {
            var id = "1"
            var type = "ci_app_libraries_tests"
            let attributes: Attributes
            
            struct Attributes: Codable {
                let modules: [String: TestManagementTestsInfo.Module]
            }
        }
    }
}

public struct TestManagementTestsInfo: Codable {
    public let modules: [String: Module]
    
    public struct Module: Codable {
        public let suites: [String: Suite]
    }

    public struct Suite: Codable {
        public let tests: [String: Test]
    }

    public struct Test: Codable {
        public let properties: Properties
        
        public struct Properties: Codable {
            public let disabled: Bool
            public let quarantined: Bool
            public let attemptToFix: Bool
            
            enum CodingKeys: String, CodingKey {
                case disabled
                case quarantined
                case attemptToFix = "attempt_to_fix"
            }
        }
    }
}

