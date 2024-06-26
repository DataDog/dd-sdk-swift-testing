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
    var libraryVersion: String
    var applicationName: String
    var version: String
    var environment: String
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
    
    var logger: Logger

    public init(serviceName: String, libraryVersion: String, applicationName: String, applicationVersion: String, environment: String, hostname: String?, apiKey: String, endpoint: Endpoint, payloadCompression: Bool = true, source: String = "ios", performancePreset: PerformancePreset = .default, exporterId: String, logger: Logger) {
        self.serviceName = serviceName
        self.libraryVersion = libraryVersion
        self.applicationName = applicationName
        self.version = applicationVersion
        self.environment = environment
        self.hostname = hostname
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.payloadCompression = payloadCompression
        self.source = source
        self.performancePreset = performancePreset
        self.exporterId = exporterId
        self.logger = logger
    }
}
