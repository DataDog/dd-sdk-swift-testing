/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import OpenTelemetrySdk

internal class SpansExporter {
    let spansDirectory = "com.datadog.civisibility/spans/v1"
    let configuration: ExporterConfiguration
    let spansStorage: FeatureStorage
    let spansUpload: FeatureUpload

    init(config: ExporterConfiguration) throws {
        self.configuration = config

        let filesOrchestrator = FilesOrchestrator(
            directory: try Directory(withSubdirectoryPath: spansDirectory),
            performance: configuration.performancePreset,
            dateProvider: SystemDateProvider()
        )

        let metadataInfo = """
        "runtime-id": "\(UUID().uuidString)",
        "language": "swift",
        "runtime.name": "\(configuration.runtimeName)",
        "runtime.version": "\(configuration.runtimeVersion)",
        "library_version": "\(configuration.libraryVersion)",
        "env": "\(configuration.environment)",
        "service": "\(configuration.serviceName)"
        """

        let prefix = """
        {"version": 1, "metadata": { \(metadataInfo)}, "events": [
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

        let requestBuilder = RequestBuilder(
            url: configuration.endpoint.spansURL,
            queryItems: [],
            headers: [
                .contentTypeHeader(contentType: .applicationJSON),
                .userAgentHeader(
                    appName: configuration.applicationName,
                    appVersion: configuration.version,
                    device: Device.current
                ),
                .ddAPIKeyHeader(apiKey: config.apiKey),
                .ddEVPOriginHeader(source: configuration.source),
                .ddEVPOriginVersionHeader(version: configuration.version),
                .ddRequestIDHeader(),
            ] + (configuration.payloadCompression ? [RequestBuilder.HTTPHeader.contentEncodingHeader(contentEncoding: .deflate)] : [])
        )

        spansUpload = FeatureUpload(featureName: "spansUpload",
                                    storage: spansStorage,
                                    requestBuilder: requestBuilder,
                                    performance: configuration.performancePreset)
    }

    func exportSpan(span: SpanData) {
        let ciTestEnvelope: CITestEnvelope
        if let spanType = span.attributes["type"] {
            ciTestEnvelope = CITestEnvelope(spanType: spanType.description,
                                            content: DDSpan(spanData: span, configuration: configuration))
        } else {
            ciTestEnvelope = CITestEnvelope(spanType: "span",
                                            content: DDSpan(spanData: span, configuration: configuration))
        }

        if configuration.performancePreset.synchronousWrite {
            spansStorage.writer.writeSync(value: ciTestEnvelope)
        } else {
            spansStorage.writer.write(value: ciTestEnvelope)
        }
    }
}
