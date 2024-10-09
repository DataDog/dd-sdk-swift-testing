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
    /// Datadog Endpoint
    var endpoint: Endpoint = .us1
    /// Session name
    var sessionName: String? = nil
    
    /// Instrumentation configuration values
    var disableNetworkInstrumentation: Bool = false
    var disableHeadersInjection: Bool = false
    var enableRecordPayload: Bool = false
    var disableNetworkCallStack: Bool = false
    var enableNetworkCallStackSymbolicated: Bool = false
    var maxPayloadSize: UInt = 1024
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
    var codeCoveragePriority: CodeCoveragePriority = .utility
    
    /// Auto Test Retries
    var testRetriesEnabled: Bool = true
    var testRetriesTestRetryCount: UInt = 5
    var testRetriesTotalRetryCount: UInt = 1000
    
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
    var extraDebugCodeCoverage: Bool = false
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
        
        sessionName = env[.sessionName]
        
        /// Instrumentation configuration values
        disableNetworkInstrumentation = env[.disableNetworkInstrumentation] ?? false
        disableHeadersInjection = env[.disableHeadersInjection] ?? false
        extraHTTPHeaders = env[.instrumentationExtraHeaders]
        excludedURLS = env[.excludedURLs]
        enableRecordPayload = env[.enableRecordPayload] ?? false
        disableNetworkCallStack = env[.disableNetworkCallStack] ?? false
        disableGitInformation = env[.disableGitInformation] ?? false
        enableNetworkCallStackSymbolicated = env[.enableNetworkCallStackSymbolicated] ?? false
        maxPayloadSize = env[.maxPayloadSize] ?? maxPayloadSize

        let envLogsEnabled = env[.enableCiVisibilityLogs] ?? false
        enableStdoutInstrumentation = envLogsEnabled || env[.enableStdoutInstrumentation] ?? false
        enableStderrInstrumentation = envLogsEnabled || env[.enableStderrInstrumentation] ?? false
        
        disableRUMIntegration = env[.disableRumIntegration] ?? env[.disableSdkIosIntegration] ?? false
        disableCrashHandler = env[.disableCrashHandler] ?? false
        disableTestInstrumenting = env[.disableTestInstrumenting] ?? false
        disableSourceLocation = env[.disableSourceLocation] ?? false
        disableNTPClock = env[.disableNTPClock] ?? false
        
        /// Intelligent test runner related configuration
        gitUploadEnabled = env[.enableCiVisibilityGitUpload] ?? gitUploadEnabled
        itrEnabled = env[.enableCiVisibilityITR] ?? itrEnabled
        coverageEnabled = env[.enableCiVisibilityCodeCoverage] ?? itrEnabled
        excludedBranches = env[.ciVisibilityExcludedBranches] ?? excludedBranches
        
        /// Automatic Test Retries
        testRetriesEnabled = env[.enableCiVisibilityFlakyRetries] ?? testRetriesEnabled
        testRetriesTestRetryCount = env[.ciVisibilityFlakyRetryCount] ?? testRetriesTestRetryCount
        testRetriesTotalRetryCount = env[.ciVisibilityTotalFlakyRetryCount] ?? testRetriesTotalRetryCount
        
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
        
        codeCoveragePriority = env[.ciVisibilityCodeCoveragePriority] ?? .utility
        
        disableTracesExporting = env[.dontExport] ?? false
        reportHostname = env[.ciVisibilityReportHostname] ?? false
        extraDebugCallStack = env[.traceDebugCallStack] ?? false
        extraDebugNetwork = env[.traceDebugNetwork] ?? false
        extraDebugCodeCoverage = env[.traceDebugCodeCoverage] ?? false
        extraDebug = env[.traceDebug] ?? extraDebugCallStack || extraDebugNetwork || extraDebugCodeCoverage
        
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

extension Config: CustomDebugStringConvertible {
    var debugDescription: String {
        """
        Enabled: \(isEnabled?.description ?? "nil")
        Is In Test Mode: \(isInTestMode)
        Is Tracer Under Testing: \(isTracerUnderTesting)
        Is Binary Under UI Testing: \(isBinaryUnderUITesting)
        Is Test Observer Needed: \(isTestObserverNeeded)
        Api Key: \(apiKey.map {_ in "*****" } ?? "nil")
        Service \(service ?? "nil")
        Environment: \(environment ?? "nil")
        Endpoint: \(endpoint.exporterEndpoint)
        Tags: \(tags.map { "\n  \($0.key): \($0.value)" }.joined())
        Custom Configurations: \(customConfigurations.map { "\n  \($0.key): \($0.value)" }.joined())
        Disable Network Instrumentation: \(disableNetworkInstrumentation)
        Disable Headers Injection: \(disableHeadersInjection)
        Enable Record Payload: \(enableRecordPayload)
        Disable Network CallStack: \(disableNetworkCallStack)
        Enable Network Call Stack Symbolicated: \(enableNetworkCallStackSymbolicated)
        Max Payload Size: \(maxPayloadSize)
        Enable Stdout Instrumentation: \(enableStdoutInstrumentation)
        Enable Stderr Instrumentation: \(enableStderrInstrumentation)
        Extra HTTP Headers: \(extraHTTPHeaders ?? [])
        Excluded URLs: \(excludedURLS ?? [])
        Disable RUM Integration: \(disableRUMIntegration)
        Disable Crash Handler: \(disableCrashHandler)
        Disable Mach Crash Handler: \(disableMachCrashHandler)
        Disable Test Instrumenting: \(disableTestInstrumenting)
        Disable Source Location: \(disableSourceLocation)
        Disable NTP Clock: \(disableNTPClock)
        Disable Git Information: \(disableGitInformation)
        Git Upload Enabled: \(gitUploadEnabled)
        Coverage Enabled: \(coverageEnabled)
        ITR Enabled: \(itrEnabled)
        Excluded Branches: \(excludedBranches)
        Test Retries Enabled: \(testRetriesEnabled)
        Test Retries Count: \(testRetriesTestRetryCount)
        Test Retries Total Count: \(testRetriesTotalRetryCount)
        Code Coverage Priority: \(codeCoveragePriority)
        Disable Traces Exporting: \(disableTracesExporting)
        Report Hostname: \(reportHostname)
        Tracer Trace Id: \(tracerTraceId ?? "nil")
        Tracer Span Id: \(tracerSpanId ?? "nil")
        Message Channel UUID: \(messageChannelUUID ?? "nil")
        Extra Debug: \(extraDebug)
        Extra Debug Network: \(extraDebugNetwork)
        Extra Debug Code Coverage: \(extraDebugCodeCoverage)
        Extra Debug Call Stack: \(extraDebugCallStack)
        """
    }
}
