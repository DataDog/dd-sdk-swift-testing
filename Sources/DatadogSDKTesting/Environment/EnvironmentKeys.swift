/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal enum EnvironmentKey: String, CaseIterable {
    case isEnabled = "DD_TEST_RUNNER"
    case apiKey = "DD_API_KEY"
    case environment = "DD_ENV"
    case service = "DD_SERVICE"
    case sourcesDir = "SRCROOT"
    case tags = "DD_TAGS"
    case disableTestInstrumenting = "DD_DISABLE_TEST_INSTRUMENTING"
    case disableNetworkInstrumentation = "DD_DISABLE_NETWORK_INSTRUMENTATION"
    case disableHeadersInjection = "DD_DISABLE_HEADERS_INJECTION"
    case instrumentationExtraHeaders = "DD_INSTRUMENTATION_EXTRA_HEADERS"
    case excludedURLs = "DD_EXCLUDED_URLS"
    case enableRecordPayload = "DD_ENABLE_RECORD_PAYLOAD"
    case disableNetworkCallStack = "DD_DISABLE_NETWORK_CALL_STACK"
    case enableNetworkCallStackSymbolicated = "DD_ENABLE_NETWORK_CALL_STACK_SYMBOLICATED"
    case disableRumIntegration = "DD_DISABLE_RUM_INTEGRATION"
    case maxPayloadSize = "DD_MAX_PAYLOAD_SIZE"
    case enableStdoutInstrumentation = "DD_ENABLE_STDOUT_INSTRUMENTATION"
    case enableStderrInstrumentation = "DD_ENABLE_STDERR_INSTRUMENTATION"
    case disableSdkIosIntegration = "DD_DISABLE_SDKIOS_INTEGRATION"
    case disableCrashHandler = "DD_DISABLE_CRASH_HANDLER"
    case disableMachCrashHandler = "DD_DISABLE_MACH_CRASH_HANDLER"
    case site = "DD_SITE"
    case endpoint = "DD_ENDPOINT"
    case dontExport = "DD_DONT_EXPORT"
    case traceDebug = "DD_TRACE_DEBUG"
    case traceDebugCallStack = "DD_TRACE_DEBUG_CALLSTACK"
    case disableNTPClock = "DD_DISABLE_NTPCLOCK"
    case enableCiVisibilityLogs = "DD_CIVISIBILITY_LOGS_ENABLED"
    case enableCiVisibilityGitUpload = "DD_CIVISIBILITY_GIT_UPLOAD_ENABLED"
    case enableCiVisibilityCodeCoverage = "DD_CIVISIBILITY_CODE_COVERAGE_ENABLED"
    case enableCiVisibilityITR = "DD_CIVISIBILITY_ITR_ENABLED"
    case ciVisibilityExcludedBranches = "DD_CIVISIBILITY_EXCLUDED_BRANCHES"
    case ciVisibilityReportHostname = "DD_CIVISIBILITY_REPORT_HOSTNAME"
    case disableSourceLocation = "DD_DISABLE_SOURCE_LOCATION"
    case applicationKey = "DD_APPLICATION_KEY"
    case appKey = "DD_APP_KEY"
    case localTestEnvironmentPort = "DD_LOCAL_TEST_ENVIRONMENT_PORT"
    case disableGitInformation = "DD_DISABLE_GIT_INFORMATION"
    case testOutputFile = "TEST_OUTPUT_FILE"
    case tracerTraceId = "ENVIRONMENT_TRACER_TRACEID"
    case tracerSpanId = "ENVIRONMENT_TRACER_SPANID"
    case messageChannelUUID = "CI_VISIBILITY_MESSAGE_CHANNEL_UUID"
    case testExecutionId = "CI_VISIBILITY_TEST_EXECUTION_ID"
}

extension EnvironmentKey {
    // These configuration values must be passed to the child app in an UI test
    static var childKeys: [Self] {
        [.isEnabled, .apiKey, .environment, .service, .sourcesDir, .tags,
         .disableTestInstrumenting, .disableNetworkInstrumentation, .disableHeadersInjection,
         .instrumentationExtraHeaders, .excludedURLs, .enableRecordPayload, disableNetworkCallStack,
         .enableNetworkCallStackSymbolicated, .disableRumIntegration, .maxPayloadSize,
         .enableCiVisibilityLogs, .enableStdoutInstrumentation, .enableStderrInstrumentation,
         .disableSdkIosIntegration, .disableCrashHandler, .disableMachCrashHandler,
         .site, .endpoint, .dontExport, .traceDebug, .traceDebugCallStack, .disableNTPClock]
    }
}

// ConfigKey reader extensions
internal extension EnvironmentReader {
    @inlinable
    func has(_ key: EnvironmentKey) -> Bool {
        has(key.rawValue)
    }
    
    @inlinable
    func has(env key: EnvironmentKey) -> Bool {
        has(env: key.rawValue)
    }
    
    @inlinable
    func has(info key: EnvironmentKey) -> Bool {
        has(info: key.rawValue)
    }
    
    @inlinable
    func get<V: EnvironmentValue>(_ key: EnvironmentKey, _ type: V.Type = V.self) -> V? {
        get(key.rawValue, type)
    }
    
    @inlinable
    func get<V: EnvironmentValue>(env key: EnvironmentKey, _ type: V.Type = V.self) -> V? {
        get(env: key.rawValue, type)
    }
    
    @inlinable
    func get<V: EnvironmentValue>(info key: EnvironmentKey, _ type: V.Type = V.self) -> V? {
        get(env: key.rawValue, type)
    }
    
    @inlinable
    subscript<V: EnvironmentValue>(key: EnvironmentKey, type: V.Type = V.self) -> V? { return get(key, type) }
}
