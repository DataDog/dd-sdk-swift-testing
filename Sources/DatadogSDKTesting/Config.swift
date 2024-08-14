/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

final class Config {
    var isEnabled: Bool? = nil
    var isInTestMode: Bool = false
    var isBinaryUnderUITesting: Bool = false
    var isTestObserverNeeded: Bool = false
    
    /// Datatog Configuration values
    var apiKey: String? = nil
    var service: String? = nil
    var tags: [String: String] = [:]
    var customConfigurations: [String: String] = [:]
    var environment: String? = nil
    
    /// Instrumentation configuration values
    var disableNetworkInstrumentation: Bool = false
    var disableHeadersInjection: Bool = false
    var enableRecordPayload: Bool = false
    var disableNetworkCallStack: Bool = false
    var enableNetworkCallStackSymbolicated: Bool = false
    var maxPayloadSize: Int? = nil
    var enableStdoutInstrumentation: Bool = false
    var enableStderrInstrumentation: Bool = false
    var extraHTTPHeaders: Set<String>? = nil
    var excludedURLS: Set<String>? = nil
    var disableRUMIntegration: Bool = false
    var disableCrashHandler: Bool = false
    var disableMachCrashHandler: Bool = false
    var disableTestInstrumenting: Bool = false
    var disableSourceLocation: Bool = false
    var disableNTPClock: Bool = false
    var disableGitInformation: Bool = false
    
    /// Intelligent test runner related environment
    var gitUploadEnabled: Bool = true
    var coverageEnabled: Bool = true
    var itrEnabled: Bool = true
    var excludedBranches: Set<String> = []
    
    /// Datadog Endpoint
    var endpoint: Endpoint = .us1
    
    /// Avoids configuring the traces exporter
    var disableTracesExporting: Bool = false

    /// Avoids configuring the traces exporter
    var reportHostname: Bool = false
    
    /// The tracer is being tested itself
    var isTracerUnderTesting: Bool = false
    
    /// Environment trace Information (Used when running in an app under UI testing)
    var tracerTraceId: String? = nil
    var tracerSpanId: String? = nil
    
    /// UUID for message channels between App and tests
    var messageChannelUUID: String? = nil
    
    /// The framework has been launched with extra debug information
    var extraDebug: Bool = false
    var extraDebugNetwork: Bool = false
    var extraDebugCallStack: Bool = false
    
    init(env: EnvironmentReader? = nil) {
        guard let env = env else { return }
        
        isEnabled = env.has(.isEnabled) ? env[.isEnabled] ?? false : nil
        
        apiKey = env[.apiKey] ?? env.get(info: "DatadogApiKey")
        environment = env[.environment]
        
        let tracerUnderTesting = env.has(env: .testOutputFile)
        isTracerUnderTesting = tracerUnderTesting
        service = env[.service].map {
            tracerUnderTesting ? $0 + "-internal-tests" : $0
        }
        
        tags = Config.expand(tags: env[.tags] ?? [:], env: env)
        let customConf = tags.compactMap {
            $0.key.hasPrefix("test.configuration.")
                ? (String($0.key.dropFirst("test.configuration.".count)), $0.value)
                : nil
        }
        customConfigurations = Dictionary(uniqueKeysWithValues: customConf)
        
        /// Instrumentation configuration values
        disableNetworkInstrumentation = env[.disableNetworkInstrumentation] ?? false
        disableHeadersInjection = env[.disableHeadersInjection] ?? false
        extraHTTPHeaders = env[.instrumentationExtraHeaders]
        excludedURLS = env[.excludedURLs]
        enableRecordPayload = env[.enableRecordPayload] ?? false
        disableNetworkCallStack = env[.disableNetworkCallStack] ?? false
        disableGitInformation = env[.disableGitInformation] ?? false
        enableNetworkCallStackSymbolicated = env[.enableNetworkCallStackSymbolicated] ?? false
        maxPayloadSize = env[.maxPayloadSize]

        let envLogsEnabled = env[.enableCiVisibilityLogs] ?? false
        enableStdoutInstrumentation = envLogsEnabled || env[.enableStdoutInstrumentation] ?? false
        enableStderrInstrumentation = envLogsEnabled || env[.enableStderrInstrumentation] ?? false
        
        disableRUMIntegration = env[.disableRumIntegration] ?? env[.disableSdkIosIntegration] ?? false
        disableCrashHandler = env[.disableCrashHandler] ?? false
        disableTestInstrumenting = env[.disableTestInstrumenting] ?? false
        disableSourceLocation = env[.disableSourceLocation] ?? false
        disableNTPClock = env[.disableNTPClock] ?? false
        
        /// Intelligent test runner related configuration
        gitUploadEnabled = env[.enableCiVisibilityGitUpload] ?? true
        
        // ITR
        itrEnabled = env[.enableCiVisibilityITR] ?? true
        coverageEnabled = env[.enableCiVisibilityCodeCoverage] ?? itrEnabled
        excludedBranches = env[.ciVisibilityExcludedBranches] ?? []
        
        /// UI testing properties
        tracerTraceId = env[.tracerTraceId]
        tracerSpanId = env[.tracerSpanId]
        
        messageChannelUUID = env[.messageChannelUUID]
        
        if let endpt = env[.site, Endpoint.self] {
            endpoint = endpt
        } else if let custom = env[.customURL, URL.self] {
            endpoint = .other(testsBaseURL: custom, logsBaseURL: custom)
        } else if let port = env[.localTestEnvironmentPort, Int.self], port < 65535 {
            let url = URL(string: "http://localhost:\(port)")!
            endpoint = .other(testsBaseURL: url, logsBaseURL: url)
        }
        
        disableTracesExporting = env[.dontExport] ?? false
        reportHostname = env[.ciVisibilityReportHostname] ?? false
        extraDebugCallStack = env[.traceDebugCallStack] ?? false
        extraDebugNetwork = env[.traceDebugNetwork] ?? false
        extraDebug = env[.traceDebug] ?? extraDebugCallStack || extraDebugNetwork
        
        disableMachCrashHandler = env[.disableMachCrashHandler] ?? extraDebug
        
        isInTestMode = env.has("XCInjectBundleInto") || env.has("XCTestConfigurationFilePath") ||
            env.has("XCTestBundlePath") || env.has("SDKROOT") || tracerSpanId != nil
        isBinaryUnderUITesting = tracerSpanId != nil && tracerTraceId != nil
        isTestObserverNeeded = !isBinaryUnderUITesting || env.has("TEST_CLASS")
    }
    
    private static func expand(tags: [String: String], env: EnvironmentReader) -> [String: String] {
        tags.mapValues { value in
            guard value.hasPrefix("$") else { return value }
            var auxValue = value.dropFirst()
            let environmentPrefix = auxValue.unicodeScalars.prefix {
                Environment.environmentCharset.contains($0)
            }
            if let environmentValue = env[String(environmentPrefix), String.self] {
                auxValue.replaceSubrange(
                    auxValue.startIndex..<auxValue.index(auxValue.startIndex, offsetBy: environmentPrefix.count),
                    with: environmentValue
                )
                return String(auxValue)
            }
            return value
        }
    }
}
