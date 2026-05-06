/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

internal class ITRService {
    let exporterConfiguration: ExporterConfiguration

    let searchCommitUploader: DataUploader
    let packFileUploader: DataUploader
    var packFileRequestBuilder: MultipartRequestBuilder
    let skippableTestsUploader: DataUploader

    init(config: ExporterConfiguration) throws {
        self.exporterConfiguration = config

        let searchCommitRequestBuilder = SingleRequestBuilder(
            url: exporterConfiguration.endpoint.searchCommitsURL,
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
            ] //+ (exporterConfiguration.payloadCompression ? [HTTPHeader.contentEncodingHeader(contentEncoding: .deflate)] : [])
        )

        packFileRequestBuilder = MultipartRequestBuilder(
            url: exporterConfiguration.endpoint.packfileURL,
            queryItems: [],
            headers: [
                .userAgentHeader(
                    appName: exporterConfiguration.applicationName,
                    appVersion: exporterConfiguration.version,
                    device: Device.current
                ),
                .apiKeyHeader(apiKey: config.apiKey),
                .traceIDHeader(traceID: config.exporterId),
                .parentSpanIDHeader(parentSpanID: config.exporterId),
                .samplingPriorityHeader()
            ] + (exporterConfiguration.payloadCompression ? [HTTPHeader.contentEncodingHeader(contentEncoding: .deflate)] : [])
        )

        let skippableTestsRequestBuilder = SingleRequestBuilder(
            url: exporterConfiguration.endpoint.skippableTestsURL,
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

        searchCommitUploader = DataUploader(
            httpClient: HTTPClient(debug: config.debug.logNetworkRequests),
            requestBuilder: searchCommitRequestBuilder
        )

        packFileUploader = DataUploader(
            httpClient: HTTPClient(debug: config.debug.logNetworkRequests),
            requestBuilder: packFileRequestBuilder
        )

        skippableTestsUploader = DataUploader(
            httpClient: HTTPClient(debug: config.debug.logNetworkRequests),
            requestBuilder: skippableTestsRequestBuilder
        )
    }

    func searchExistingCommits(
        repositoryURL: String, commits: [String]
    ) throws(LibraryConfigurationCommunicationError) -> [String] {
        let commitPayload = CommitRequesFormat(repositoryURL: repositoryURL, commits: commits)
        let payloadString = commitPayload.jsonString

        guard let jsonData = commitPayload.jsonData else {
            throw LibraryConfigurationCommunicationError(
                requestName: "SearchCommitsRequest",
                payload: payloadString,
                reason: .payloadEncodingFailed
            )
        }

        let response: Data
        switch searchCommitUploader.uploadWithResult(data: jsonData) {
        case .success(let data):
            response = data
        case .failure(let error):
            throw LibraryConfigurationCommunicationError(
                requestName: "SearchCommitsRequest",
                payload: payloadString,
                reason: error.isUnauthorized ? .unauthorized : .communicationFailed(error)
            )
        }

        let commitResponse: CommitResponseFormat
        do {
            commitResponse = try JSONDecoder().decode(CommitResponseFormat.self, from: response)
        } catch {
            throw LibraryConfigurationCommunicationError(
                requestName: "SearchCommitsRequest",
                payload: payloadString,
                reason: .responseDecodingFailed(body: response, error: error)
            )
        }

        return commitResponse.data.map { $0.id }
    }

    func uploadPackFiles(packFilesDirectory: Directory, commit: String, repository: String) throws {
        Log.debug("Uploading packfiles from: \(packFilesDirectory) for commit: \(commit) in repo: \(repository)")
        try packFilesDirectory.files()
            .filter { $0.name.hasSuffix(".pack") }
            .forEach {
                packFileRequestBuilder.addFieldsCallback = { request, data in
                    request.addDataField(named: "packfile", data: data, mimeType: .applicationOctetStream)
                    request.addDataField(named: "pushedSha", data: PushedSHA(id: commit, repoURL: repository).bytes!, mimeType: .applicationJSON)
                }
                _ = packFileUploader.upload(data: try $0.read())
            }
    }

    func skippableTests(repositoryURL: String, sha: String, testLevel: ITRTestLevel,
                        configurations: [String: String], customConfigurations: [String: String]
    ) throws(LibraryConfigurationCommunicationError) -> SkipTests {
        var itrConfig: [String: JSONGeneric] = configurations.mapValues { .string($0) }
        itrConfig["custom"] = .init(customConfigurations)

        let skippablePayload = SkipTestsRequestFormat(env: exporterConfiguration.environment,
                                                      service: exporterConfiguration.serviceName,
                                                      repositoryURL: repositoryURL,
                                                      sha: sha,
                                                      testLevel: testLevel,
                                                      configurations: itrConfig)
        let payloadString = skippablePayload.jsonString

        guard let jsonData = skippablePayload.jsonData else {
            throw LibraryConfigurationCommunicationError(
                requestName: "SkipTestsRequest",
                payload: payloadString,
                reason: .payloadEncodingFailed
            )
        }

        let response: Data
        switch skippableTestsUploader.uploadWithResult(data: jsonData) {
        case .success(let data):
            response = data
        case .failure(let error):
            throw LibraryConfigurationCommunicationError(
                requestName: "SkipTestsRequest",
                payload: payloadString,
                reason: error.isUnauthorized ? .unauthorized : .communicationFailed(error)
            )
        }

        let skipTests: SkipTestsResponseFormat
        do {
            skipTests = try JSONDecoder().decode(SkipTestsResponseFormat.self, from: response)
        } catch {
            throw LibraryConfigurationCommunicationError(
                requestName: "SkipTestsRequest",
                payload: payloadString,
                reason: .responseDecodingFailed(body: response, error: error)
            )
        }

        let tests = skipTests.data.map { skipTest in
            let customConfigurations: [String: String]?
            if case .object(let dict) = skipTest.attributes.configurations?["custom"] {
                customConfigurations = dict.compactMapValues {
                    switch $0 {
                    case .string(let s): return s
                    default: return nil
                    }
                }
            } else {
                customConfigurations = nil
            }

            let configurations: [String: String]? = skipTest.attributes.configurations?.compactMapValues {
                switch $0 {
                    case .string(let string):
                        return string
                    default:
                        return nil
                }
            }

            return SkipTestPublicFormat(name: skipTest.attributes.name,
                                        suite: skipTest.attributes.suite,
                                        configuration: configurations,
                                        customConfiguration: customConfigurations)
        }
        return SkipTests(correlationId: skipTests.meta.correlationId, tests: tests)
    }
}

private struct PushedSHA: Encodable {
    struct _Data: Encodable {
        let id: String
        let type: String
    }
    
    struct _Meta: Encodable {
        let repositoryUrl: String
        
        enum CodingKeys: String, CodingKey {
            case repositoryUrl = "repository_url"
        }
    }
    
    let data: _Data
    let meta: _Meta
    
    init(id: String, repoURL: String) {
        data = _Data(id: id, type: "commit")
        meta = _Meta(repositoryUrl: repoURL)
    }
    
    var bytes: Data? { try? JSONEncoder().encode(self) }
}
