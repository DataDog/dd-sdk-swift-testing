/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct ExporterError: Error, CustomStringConvertible {
    let description: String
}

public struct ExporterConfiguration: Sendable {
    /// Performance preset for the file-backed reader/writer pipelines.
    var performancePreset: PerformancePreset

    var metadata: SpanMetadata

    var environment: String {
        didSet { _setEnv() }
    }

    var logger: Logger

    public init(environment: String, metadata: SpanMetadata,
                performancePreset: PerformancePreset = .default,
                logger: Logger)
    {
        self.performancePreset = performancePreset
        self.metadata = metadata
        self.logger = logger
        self.environment = environment
        _setEnv()
    }

    private mutating func _setEnv() {
        metadata[string: "env"] = environment
    }
}
