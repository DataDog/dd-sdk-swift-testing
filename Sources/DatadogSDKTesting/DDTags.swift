/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct DDTags {
    /// A Datadog-specific span tag, which sets the value appearing in the "RESOURCE" column
    /// in traces explorer on [app.datadoghq.com](https://app.datadoghq.com/)
    /// Can be used to customize the resource names grouped under the same operation name.
    ///
    /// Expected value: `Bool`
    static let error = "error"
    
    /// Expects `String` value set for a tag.
    static let resource = "resource.name"

    /// Those keys used to encode information received from the user through `OpenTracingLogFields`, `OpenTracingTagKeys` or custom fields.
    /// Supported by Datadog platform.
    static let errorType    = "error.type"
    static let errorMessage = "error.msg"
    static let errorStack   = "error.stack"

    /// Default span type for spans created without a specifying a type. In general all spans should use this type.
    static let defaultSpanType = "custom"


    /// Expected value: `String`
    public static let httpMethod = "http.method"
    /// Expected value: `Int`
    public static let httpStatusCode = "http.status_code"
    /// Expected value: `String`
    public static let httpUrl = "http.url"
}


internal struct DDTestingTags {
    static let testSuite       = "test.suite"
    static let testName        = "test.name"
    static let testFramework   = "test.framework"
    static let testTraits      = "test.traits"
    static let testCode        = "test.code"

    static let testType        = "test.type"
    static let typeTest        = "test"
    static let typeBenchmark   = "benchmark"

    static let testStatus      = "test.status"
    static let statusPass      = "pass"
    static let statusFail      = "fail"
    static let statusSkip      = "skip"

    static let type            = "type"

    static let logSource       = "source"
}

internal struct DDCITags {
    static let gitRepository    = "git.repository_url"
    static let gitCommit        = "git.commit_sha"
    static let gitBranch        = "git.branch"
    static let gitTag           = "git.tag"

    static let buildSourceRoot  = "build.source_root"

    static let ciProvider       = "ci.provider.name"
    static let ciPipelineId     = "ci.pipeline.id"
    static let ciPipelineNumber = "ci.pipeline.number"
    static let ciPipelineURL    = "ci.pipeline.url"
    static let ciPipelineName    = "ci.pipeline.name"
    static let ciJobURL         = "ci.job.url"
    static let ciWorkspacePath  = "ci.workspace_path"
}

internal struct DDBenchmarkingTags {
    static let durationMean                 = "benchmark.duration.mean"
    static let benchmarkRuns                = "benchmark.runs"
    static let memoryTotalBytes             = "benchmark.memory.total_bytes_allocations"
    static let memoryMeanBytes_allocations  = "benchmark.memory.mean_bytes_allocations"
}
