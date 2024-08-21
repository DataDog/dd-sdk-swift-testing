/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

internal class SpansExporter {
    let spansDirectory = "com.datadog.civisibility/spans/v1"
    let configuration: ExporterConfiguration
    let spansStorage: FeatureStorage
    let spansUpload: FeatureUpload
    let runtimeId = UUID().uuidString

    init(config: ExporterConfiguration) throws {
        self.configuration = config

        let filesOrchestrator = FilesOrchestrator(
            directory: try Directory(withSubdirectoryPath: spansDirectory),
            performance: configuration.performancePreset,
            dateProvider: SystemDateProvider()
        )

        let genericMetadata = """
        "*": { "env": "\(configuration.environment)", "runtime-id": "\(runtimeId)", "language": "swift", "library_version": "\(configuration.libraryVersion)"}
        """

        let prefix = """
        {"version": 1, "metadata": { \(genericMetadata) }, "events": [
        """

        let suffix = "]}"

        let dataFormat = DataFormat(prefix: prefix, suffix: suffix, separator: ",")

        let spanFileWriter = FileWriter(
            dataFormat: dataFormat,
            orchestrator: filesOrchestrator
        )

        let spanFileReader = FileReader(
            dataFormat: dataFormat,
            orchestrator: filesOrchestrator
        )

        spansStorage = FeatureStorage(writer: spanFileWriter, reader: spanFileReader)

        let requestBuilder = SingleRequestBuilder(
            url: configuration.endpoint.spansURL,
            queryItems: [],
            headers: [
                .contentTypeHeader(contentType: .applicationJSON),
                .userAgentHeader(
                    appName: configuration.applicationName,
                    appVersion: configuration.version,
                    device: Device.current
                ),
                .apiKeyHeader(apiKey: config.apiKey) ] +
            (configuration.payloadCompression ? [HTTPHeader.contentEncodingHeader(contentEncoding: .deflate)] : []) +
            ((configuration.hostname != nil) ? [HTTPHeader.hostnameHeader(hostname: configuration.hostname!)] : [])
        )

        spansUpload = FeatureUpload(featureName: "spansUpload",
                                    storage: spansStorage,
                                    requestBuilder: requestBuilder,
                                    performance: configuration.performancePreset,
                                    debug: config.debug.logNetworkRequests)
    }

    func exportSpan(span: SpanData) {
        if span.attributes["type"]?.description == "test" {
            let ciTestEnvelope = CITestEnvelope(DDSpan(spanData: span, serviceName: configuration.serviceName, applicationVersion: configuration.version))
            if configuration.performancePreset.synchronousWrite {
                spansStorage.writer.writeSync(value: ciTestEnvelope)
            } else {
                spansStorage.writer.write(value: ciTestEnvelope)
            }
        } else {
            let spanEnvelope = SpanEnvelope(DDSpan(spanData: span, serviceName: configuration.serviceName, applicationVersion: configuration.version))
            if configuration.performancePreset.synchronousWrite {
                spansStorage.writer.writeSync(value: spanEnvelope)
            } else {
                spansStorage.writer.write(value: spanEnvelope)
            }
        }
    }
}
