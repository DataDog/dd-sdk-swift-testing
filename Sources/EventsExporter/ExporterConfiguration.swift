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
    
    /// Exporter Id
    var exporterId: String

    /// Events source
    var source: String
    
    /// Application Version
    var applicationVersion: String
    
    /// Performance preset for reporting
    var performancePreset: PerformancePreset
    
    var metadata: SpanMetadata
    
    var environment: String {
        didSet { _setEnv() }
    }
    
    var logger: Logger
    var debugSaveCodeCoverageFilesAt: URL?

    public init(
        serviceName: String,
        environment: String,
        version: String,
        metadata: SpanMetadata,
        source: String = "ios",
        performancePreset: PerformancePreset = .default,
        exporterId: String,
        logger: Logger,
        debugSaveCodeCoverageFilesAt: URL? = nil
    ) {
        self.serviceName = serviceName
        self.source = source
        self.applicationVersion = version
        self.performancePreset = performancePreset
        self.exporterId = exporterId
        self.metadata = metadata
        self.logger = logger
        self.debugSaveCodeCoverageFilesAt = debugSaveCodeCoverageFilesAt
        self.environment = environment
        _setEnv()
    }
    
    private mutating func _setEnv() {
        metadata[string: "env"] = environment
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
