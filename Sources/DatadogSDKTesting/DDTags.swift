/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

internal enum DDTags {
    /// A Datadog-specific span tag, which sets the value appearing in the "RESOURCE" column
    /// in traces explorer on [app.datadoghq.com](https://app.datadoghq.com/)
    /// Can be used to customize the resource names grouped under the same operation name.
    ///

    /// Those keys used to encode information received from the user through `OpenTracingLogFields`, `OpenTracingTagKeys` or custom fields.
    /// Supported by Datadog platform.
    static let errorType = "error.type"
    static let errorMessage = "error.message"
    static let errorStack = "error.stack"

    /// Default span type for spans created without a specifying a type. In general all spans should use this type.
    static let defaultSpanType = "custom"

    /// Expected value: `String`
    static let httpMethod = "http.method"
    /// Expected value: `Int`
    static let httpStatusCode = "http.status_code"
    /// Expected value: `String`
    static let httpUrl = "http.url"
}

internal enum DDGenericTags {
    static let type = "type"
    static let resourceName = "resource.name"
    static let origin = "_dd.origin"
}

internal enum DDTestTags {
    static let testName = "test.name"
    static let testSuite = "test.suite"
    static let testBundle = "test.bundle"
    static let testFramework = "test.framework"
    static let testType = "test.type"
    static let testStatus = "test.status"
    static let testSourceFile = "test.source.file"
    static let testSourceStartLine = "test.source.start"
    static let testSourceEndLine = "test.source.end"
    static let testExecutionOrder = "test.execution.order"
    static let testExecutionProcessId = "test.execution.processId"
    static let testCodeowners = "test.codeowners"
    static let testIsUITest = "test.is_ui_test"
}

internal enum DDOSTags {
    static let osPlatform = "os.platform"
    static let osArchitecture = "os.architecture"
    static let osVersion = "os.version"
}

internal enum DDDeviceTags {
    static let deviceName = "device.name"
    static let deviceModel = "device.model"
}

internal enum DDRuntimeTags {
    static let runtimeName = "runtime.name"
    static let runtimeVersion = "runtime.version"
}

internal enum DDTracerTags {
    static let tracerLanguage = "tracer.language"
    static let tracerVersion = "tracer.version"
}

internal enum DDGitTags {
    static let gitRepository = "git.repository_url"
    static let gitBranch = "git.branch"
    static let gitTag = "git.tag"
    static let gitCommit = "git.commit.sha"
    static let gitCommitMessage = "git.commit.message"
    static let gitAuthorName = "git.commit.author.name"
    static let gitAuthorEmail = "git.commit.author.email"
    static let gitAuthorDate = "git.commit.author.date"
    static let gitCommitterName = "git.commit.committer.name"
    static let gitCommitterEmail = "git.commit.committer.email"
    static let gitCommitterDate = "git.commit.committer.date"
}

internal enum DDCITags {
    static let ciProvider = "ci.provider.name"
    static let ciPipelineId = "ci.pipeline.id"
    static let ciPipelineName = "ci.pipeline.name"
    static let ciPipelineNumber = "ci.pipeline.number"
    static let ciPipelineURL = "ci.pipeline.url"
    static let ciStageName = "ci.stage.name"
    static let ciJobName = "ci.job.name"
    static let ciJobURL = "ci.job.url"
    static let ciWorkspacePath = "ci.workspace_path"
}

internal enum DDBenchmarkTags {
    static let benchmark = "benchmark"
    static let benchmarkMean = "mean"
    static let benchmarkRun = "run"
    static let benchmarkInfo = "info"

    static let statisticsN = "statistics.n"
    static let statisticsMax = "statistics.max"
    static let statisticsMin = "statistics.min"
    static let statisticsMean = "statistics.mean"
    static let statisticsMedian = "statistics.median"
    static let statisticsStdDev = "statistics.std_dev"
    static let statisticsStdErr = "statistics.std_err"
    static let statisticsKurtosis = "statistics.kurtosis"
    static let statisticsSkewness = "statistics.skewness"
    static let statisticsP99 = "statistics.p99"
    static let statisticsP95 = "statistics.p95"
    static let statisticsP90 = "statistics.p90"
}

internal enum DDBenchmarkMeasuresTags: String {
    case duration
    case system_time
    case user_time
    case run_time
    case transient_vm_allocations
    case persistent_vm_allocations
    case temporary_heap_allocations
    case persistent_heap_allocations
    case persistent_heap_allocations_nodes
    case transient_heap_allocations
    case transient_heap_allocations_nodes
    case total_heap_allocations
    case memory_physical_peak
    case memory_physical
    case high_water_mark_vm_allocations
    case high_water_mark_heap_allocations
    case application_launch
    case clock_time_monotonic
    case cpu_instructions_retired
    case cpu_cycles
    case cpu_time
    case disk_logical_writes
    case disk_logical_reads
}

internal enum DDTagValues {
    static let originCiApp = "ciapp-test"

    static let typeBenchmark = "benchmark"
    static let typeTest = "test"

    static let statusPass = "pass"
    static let statusFail = "fail"
    static let statusSkip = "skip"
}
