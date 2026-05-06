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
        repositoryURL: String, sha: String? = nil, commitMessage: String? = nil, module: String? = nil, branch: String? = nil
    ) throws(LibraryConfigurationCommunicationError) -> TestManagementTestsInfo {
        let testsPayload = TestsRequest(repositoryURL: repositoryURL, sha: sha, commitMessage: commitMessage, module: module, branch: branch)
        let payloadString = testsPayload.jsonString

        guard let jsonData = testsPayload.jsonData else {
            throw LibraryConfigurationCommunicationError(
                requestName: "Test Management Tests Request",
                payload: payloadString,
                reason: .payloadEncodingFailed
            )
        }

        let response: Data
        switch testsUploader.uploadWithResult(data: jsonData) {
        case .success(let data):
            response = data
        case .failure(let error):
            throw LibraryConfigurationCommunicationError(
                requestName: "Test Management Tests Request",
                payload: payloadString,
                reason: error.isUnauthorized ? .unauthorized : .communicationFailed(error)
            )
        }

        let settings: TestsResponse
        do {
            settings = try JSONDecoder().decode(TestsResponse.self, from: response)
        } catch {
            throw LibraryConfigurationCommunicationError(
                requestName: "Test Management Tests Request",
                payload: payloadString,
                reason: .responseDecodingFailed(body: response, error: error)
            )
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
                let branch: String?

                enum CodingKeys: String, CodingKey {
                    case repositoryURL = "repository_url"
                    case commitMessage = "commit_message"
                    case module
                    case sha
                    case branch
                }
            }
        }
        
        init(repositoryURL: String, sha: String? = nil, commitMessage: String? = nil, module: String? = nil, branch: String? = nil) {
            self.data = Data(
                attributes: Data.Attributes(
                    repositoryURL: repositoryURL, commitMessage: commitMessage, module: module, sha: sha, branch: branch
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
    
    public init(modules: [String : Module]) {
        self.modules = modules
    }
    
    public struct Module: Codable {
        public let suites: [String: Suite]
        
        public init(suites: [String : Suite]) {
            self.suites = suites
        }
    }

    public struct Suite: Codable {
        public let tests: [String: Test]
        
        public init(tests: [String : Test]) {
            self.tests = tests
        }
    }

    public struct Test: Codable {
        public let properties: Properties
        
        public init(properties: Properties) {
            self.properties = properties
        }
        
        public init(disabled: Bool = false, quarantined: Bool = false, attemptToFix: Bool = false) {
            self.init(properties: .init(disabled: disabled,
                                        quarantined: quarantined,
                                        attemptToFix: attemptToFix))
        }
        
        public struct Properties: Codable {
            public let disabled: Bool
            public let quarantined: Bool
            public let attemptToFix: Bool
            
            enum CodingKeys: String, CodingKey {
                case disabled
                case quarantined
                case attemptToFix = "attempt_to_fix"
            }
            
            public init(disabled: Bool = false, quarantined: Bool = false, attemptToFix: Bool = false) {
                self.disabled = disabled
                self.quarantined = quarantined
                self.attemptToFix = attemptToFix
            }
        }
    }
}

