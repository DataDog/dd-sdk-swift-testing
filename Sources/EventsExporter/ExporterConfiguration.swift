/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct ExporterError: Error, CustomStringConvertible {
    let description: String
}

public struct ExporterConfiguration {
    /// The name of the service, resource, version,... that will be reported to the backend.
    var serviceName: String
    var applicationName: String
    var version: String
    var hostname: String?

    /// API key for authentication
    var apiKey: String

    /// Endpoint that will be used for reporting.
    var endpoint: Endpoint
    /// Exporter will deflate payloads before sending
    var payloadCompression: Bool

    var source: String
    /// Performance preset for reporting
    var performancePreset: PerformancePreset

    /// Exporter ID for tracing
    var exporterId: String
    
    var metadata: SpanMetadata
    
    var environment: String {
        didSet { metadata[string: "env"] = environment }
    }
    
    var logger: Logger
    var debug: Debug

    public init(
        serviceName: String, applicationName: String, applicationVersion: String,
        environment: String, hostname: String?, apiKey: String,
        endpoint: Endpoint, metadata: SpanMetadata,
        payloadCompression: Bool = true, source: String = "ios",
        performancePreset: PerformancePreset = .default, exporterId: String, logger: Logger,
        debug: Debug = .init()
    ) {
        self.serviceName = serviceName
        self.applicationName = applicationName
        self.version = applicationVersion
        self.hostname = hostname
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.payloadCompression = payloadCompression
        self.source = source
        self.performancePreset = performancePreset
        self.exporterId = exporterId
        self.metadata = metadata
        self.logger = logger
        self.debug = debug
        self.environment = environment
    }
}


extension ExporterConfiguration {
    public struct Debug {
        let logNetworkRequests: Bool
        let saveCodeCoverageFiles: Bool
        
        public init(logNetworkRequests: Bool = false, saveCodeCoverageFiles: Bool = false) {
            self.logNetworkRequests = logNetworkRequests
            self.saveCodeCoverageFiles = saveCodeCoverageFiles
        }
    }
}
