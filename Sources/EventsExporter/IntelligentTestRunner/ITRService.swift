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
    let itrConfigUploader: DataUploader

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
                .apiKeyHeader(apiKey: config.apiKey),
                .applicationKeyHeader(applicationKey: config.applicationKey),
                .traceIDHeader(traceID: config.exporterId),
                .parentSpanIDHeader(parentSpanID: config.exporterId),
                .samplingPriorityHeader()
            ] // + (configuration.payloadCompression ? [HTTPHeader.contentEncodingHeader(contentEncoding: .deflate)] : [])
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
                .applicationKeyHeader(applicationKey: config.applicationKey),
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
                .apiKeyHeader(apiKey: config.apiKey),
                .applicationKeyHeader(applicationKey: config.applicationKey),
                .traceIDHeader(traceID: config.exporterId),
                .parentSpanIDHeader(parentSpanID: config.exporterId),
                .samplingPriorityHeader()
            ]
        )

        let itrConfigRequestBuilder = SingleRequestBuilder(
            url: exporterConfiguration.endpoint.itrSettingsURL,
            queryItems: [],
            headers: [
                .userAgentHeader(
                    appName: exporterConfiguration.applicationName,
                    appVersion: exporterConfiguration.version,
                    device: Device.current
                ),
                .apiKeyHeader(apiKey: config.apiKey),
                .applicationKeyHeader(applicationKey: config.applicationKey),
                .traceIDHeader(traceID: config.exporterId),
                .parentSpanIDHeader(parentSpanID: config.exporterId),
                .samplingPriorityHeader()
            ]
        )

        searchCommitUploader = DataUploader(
            httpClient: HTTPClient(),
            requestBuilder: searchCommitRequestBuilder
        )

        packFileUploader = DataUploader(
            httpClient: HTTPClient(),
            requestBuilder: packFileRequestBuilder
        )

        skippableTestsUploader = DataUploader(
            httpClient: HTTPClient(),
            requestBuilder: skippableTestsRequestBuilder
        )

        itrConfigUploader = DataUploader(
            httpClient: HTTPClient(),
            requestBuilder: itrConfigRequestBuilder
        )
    }

    func searchExistingCommits(repositoryURL: String, commits: [String]) -> [String] {
        let commitPayload = CommitRequesFormat(repositoryURL: repositoryURL, commits: commits)
        guard let jsonData = commitPayload.jsonData,
              let response = searchCommitUploader.uploadWithResponse(data: jsonData),
              let commitResponse = try? JSONDecoder().decode(CommitResponseFormat.self, from: response)
        else {
            Log.debug("CommitRequesFormat payload: \(commitPayload.jsonString)")
            Log.debug("searchCommits invalid response")
            return []
        }

        let commits = commitResponse.data.map { $0.id }
        return commits
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

    func skippableTests(repositoryURL: String, sha: String, configurations: [String: String], customConfigurations: [String: String]) -> SkipTests? {
        var itrConfig: [String: JSONGeneric] = configurations.mapValues { .string($0) }
        itrConfig["custom"] = .stringDict(customConfigurations)

        let skippablePayload = SkipTestsRequestFormat(env: exporterConfiguration.environment,
                                                      service: exporterConfiguration.serviceName,
                                                      repositoryURL: repositoryURL,
                                                      sha: sha,
                                                      configurations: itrConfig)

        Log.debug("SkipTestsRequestFormat payload: \(skippablePayload.jsonString)")
        guard let jsonData = skippablePayload.jsonData,
              let response = skippableTestsUploader.uploadWithResponse(data: jsonData)
        else {
            Log.debug("skippableTests no response")
            return nil
        }

        guard let skipTests = try? JSONDecoder().decode(SkipTestsResponseFormat.self, from: response) else {
            Log.debug("skippableTests invalid response: \(String(decoding: response, as: UTF8.self))")
            return nil
        }

        let tests = skipTests.data.map { skipTest in
            let customConfigurations: [String: String]?
            if case .stringDict(let dict) = skipTest.attributes.configuration?["custom"] {
                customConfigurations = dict
            } else {
                customConfigurations = nil
            }

            let configurations: [String: String]? = skipTest.attributes.configuration?.compactMapValues {
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
        return SkipTests(correlationId: skipTests.meta.correlation_id, tests: tests)
    }

    func itrSetting(service: String, env: String, repositoryURL: String, branch: String, sha: String, configurations: [String: String], customConfigurations: [String: String]) -> (codeCoverage: Bool, testsSkipping: Bool)? {
        var configurations: [String: JSONGeneric] = configurations.mapValues { .string($0) }
        configurations["custom"] = .stringDict(customConfigurations)

        let itrConfigPayload = ITRConfigRequesFormat(service: service, env: env, repositoryURL: repositoryURL, branch: branch, sha: sha, configurations: configurations)

        guard let jsonData = itrConfigPayload.jsonData,
              let response = itrConfigUploader.uploadWithResponse(data: jsonData)
        else {
            Log.debug("SkipTestsRequestFormat payload: \(itrConfigPayload.jsonString)")
            Log.debug("skippableTests no response")
            return nil
        }

        guard let itrConfig = try? JSONDecoder().decode(ITRConfigResponseFormat.self, from: response) else {
            Log.debug("itrSetting invalid response: \(String(decoding: response, as: UTF8.self))")
            return nil
        }
        Log.debug("itrSetting response: \(String(decoding: response, as: UTF8.self))")

        return (itrConfig.data.attributes.code_coverage, itrConfig.data.attributes.tests_skipping)
    }
}

private struct PushedSHA: Encodable {
    struct _Data: Encodable {
        let id: String
        let type: String
    }
    
    struct _Meta: Encodable {
        let repositoryUrl: String
    }
    
    let data: _Data
    let meta: _Meta
    
    init(id: String, repoURL: String) {
        data = _Data(id: id, type: "commit")
        meta = _Meta(repositoryUrl: repoURL)
    }
    
    var bytes: Data? {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try? encoder.encode(self)
    }
}
