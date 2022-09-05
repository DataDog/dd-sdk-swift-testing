/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

internal class ITRService {
    let configuration: ExporterConfiguration

    let searchCommitUploader: DataUploader
    let packFileUploader: DataUploader
    var packFileRequestBuilder: MultipartRequestBuilder
    let skippableTestsUploader: DataUploader

    init(config: ExporterConfiguration) throws {
        self.configuration = config

        let searchCommitRequestBuilder = SingleRequestBuilder(
            url: configuration.endpoint.searchCommitsURL,
            queryItems: [],
            headers: [
                .userAgentHeader(
                    appName: configuration.applicationName,
                    appVersion: configuration.version,
                    device: Device.current
                ),
                .ddAPIKeyHeader(apiKey: config.apiKey),
                .ddApplicationKeyHeader(applicationKey: config.applicationKey),
                .traceIDHeader(traceID: config.exporterId),
                .parentSpanIDHeader(parentSpanID: config.exporterId),
                .samplingPriorityHeader()
            ] // + (configuration.payloadCompression ? [HTTPHeader.contentEncodingHeader(contentEncoding: .deflate)] : [])
        )

        packFileRequestBuilder = MultipartRequestBuilder(
            url: configuration.endpoint.packfileURL,
            queryItems: [],
            headers: [
                .userAgentHeader(
                    appName: configuration.applicationName,
                    appVersion: configuration.version,
                    device: Device.current
                ),
                .ddAPIKeyHeader(apiKey: config.apiKey),
                .ddApplicationKeyHeader(applicationKey: config.applicationKey),
                .traceIDHeader(traceID: config.exporterId),
                .parentSpanIDHeader(parentSpanID: config.exporterId),
                .samplingPriorityHeader()
            ] + (configuration.payloadCompression ? [HTTPHeader.contentEncodingHeader(contentEncoding: .deflate)] : [])
        )

        let skippableTestsRequestBuilder = SingleRequestBuilder(
            url: ITRService.skippableTestsURL(originalURL: configuration.endpoint.skippableTestsURLString,
                                              env: configuration.environment,
                                              service: configuration.serviceName),
            queryItems: [],
            headers: [
                .userAgentHeader(
                    appName: configuration.applicationName,
                    appVersion: configuration.version,
                    device: Device.current
                ),
                .ddAPIKeyHeader(apiKey: config.apiKey),
                .ddApplicationKeyHeader(applicationKey: config.applicationKey),
                .traceIDHeader(traceID: config.exporterId),
                .parentSpanIDHeader(parentSpanID: config.exporterId),
                .samplingPriorityHeader()
            ] // + (configuration.payloadCompression ? [HTTPHeader.contentEncodingHeader(contentEncoding: .deflate)] : [])
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
    }

    public func searchExistingCommits(repositoryURL: String, commits: [String]) -> [String] {
        let commitPayload = CommitRequesFormat(repositoryURL: repositoryURL, commits: commits)
        guard let jsonData = commitPayload.jsonData,
              let response = searchCommitUploader.uploadWithResponse(data: jsonData),
              let commitResponse = try? JSONDecoder().decode(CommitResponseFormat.self, from: response)
        else {
            return []
        }

        let commits = commitResponse.data.map { $0.id }
        return commits
    }

    public func uploadPackFiles(packFilesDirectory: Directory, commit: String, repository: String) throws {
        try packFilesDirectory.files()
            .filter { $0.name.hasSuffix(".pack") }
            .forEach {
                packFileRequestBuilder.addFieldsCallback = { request, data in
                    request.addDataField(named: "packfile", data: data, mimeType: .applicationOctetStream)
                    request.addDataField(named: "pushedSha", data: #"{"data":{"id":"\#(commit)","type":"commit"}, "meta":{"repository_url":"\#(repository)"}}"#.data(using: .utf8)!, mimeType: .applicationJSON)
                }
                _ = packFileUploader.upload(data: try $0.read())
            }
    }

    private static func skippableTestsURL(originalURL: String, env: String, service: String) -> URL {
        return URL(string: originalURL.replacingOccurrences(of: "@1", with: env.lowercased())
            .replacingOccurrences(of: "@2", with: service.lowercased()))!
    }

    public func skippableTests(repositoryURL: String, sha: String, configurations: [String: String], customConfigurations: [String: String]) -> [SkipTestPublicFormat] {

        var itrConfig:[String: JSONGeneric] = configurations.mapValues { .string($0)}
        itrConfig["custom"] = .stringDict(customConfigurations)

        let commitPayload = SkipTestsRequestFormat(repositoryURL: repositoryURL, sha: sha, configurations: itrConfig)
        guard let jsonData = commitPayload.jsonData,
              let response = skippableTestsUploader.uploadWithResponse(data: jsonData),
              let skipTests = try? JSONDecoder().decode(SkipTestsResponseFormat.self, from: response)
        else {
            return []
        }

        return skipTests.data.map { skipTest in

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
    }
}
