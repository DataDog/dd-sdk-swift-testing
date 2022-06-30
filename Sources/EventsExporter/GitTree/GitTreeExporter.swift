/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

internal class GitTreeExporter {
    let configuration: ExporterConfiguration

    let searchCommitUploader: DataUploader
    let packFileUploader: DataUploader
    var packFileRequestBuilder: MultipartRequestBuilder

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
                .ddApplicationKeyHeader(applicationKey: config.applicationKey)
            ] //+ (configuration.payloadCompression ? [HTTPHeader.contentEncodingHeader(contentEncoding: .deflate)] : [])
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
                .ddApplicationKeyHeader(applicationKey: config.applicationKey)
            ] + (configuration.payloadCompression ? [HTTPHeader.contentEncodingHeader(contentEncoding: .deflate)] : [])
        )

        searchCommitUploader = DataUploader(
            httpClient: HTTPClient(),
            requestBuilder: searchCommitRequestBuilder
        )

        packFileUploader = DataUploader(
            httpClient: HTTPClient(),
            requestBuilder: packFileRequestBuilder
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
}
