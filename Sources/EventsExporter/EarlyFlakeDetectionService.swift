/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public typealias KnownTests = [String: [String: [String]]]

internal final class EarlyFlakeDetectionService {
    let exporterConfiguration: ExporterConfiguration
    let testsUploader: DataUploader
    
    init(config: ExporterConfiguration) throws {
        self.exporterConfiguration = config
        
        let testsRequestBuilder = SingleRequestBuilder(
            url: exporterConfiguration.endpoint.knownTestsURL,
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
        service: String, env: String, repositoryURL: String,
        configurations: [String: String], customConfigurations: [String: String]
    ) -> KnownTests? {
        var configurations: [String: JSONGeneric] = configurations.mapValues { .string($0) }
        configurations["custom"] = .stringDict(customConfigurations)
        
        let testsPayload = TestsRequest(service: service, env: env, repositoryURL: repositoryURL,
                                        configurations: configurations)

        guard let jsonData = testsPayload.jsonData,
              let response = testsUploader.uploadWithResponse(data: jsonData)
        else {
            Log.debug("EFD Tests Request payload: \(testsPayload.jsonString)")
            Log.debug("EFD Tests Request no response")
            return nil
        }

        guard let settings = try? JSONDecoder().decode(TestsResponse.self, from: response) else {
            Log.debug("EFD Tests Request invalid response: \(String(decoding: response, as: UTF8.self))")
            return nil
        }
        Log.debug("EFD Tests Request response: \(String(decoding: response, as: UTF8.self))")

        return settings.data.attributes.tests
    }
}

extension EarlyFlakeDetectionService {
    struct TestsRequest: Codable, JSONable {
        let data: Data
        
        struct Data: Codable {
            var id = "1"
            var type = "ci_app_libraries_tests_request"
            let attributes: Attributes
            
            struct Attributes: Codable {
                let repositoryURL: String
                let env: String
                let service: String
                let configurations: [String: JSONGeneric]
                
                enum CodingKeys: String, CodingKey {
                    case service
                    case env
                    case repositoryURL = "repository_url"
                    case configurations
                }
            }
        }
        
        init(
            service: String, env: String, repositoryURL: String,
            configurations: [String: JSONGeneric]
        ) {
            self.data = Data(
                attributes: Data.Attributes(
                    repositoryURL: repositoryURL, env: env, service: service,
                    configurations: configurations
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
                let tests: KnownTests
            }
        }
    }
}
