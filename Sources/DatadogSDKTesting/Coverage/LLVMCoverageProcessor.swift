/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@preconcurrency internal import CodeCoverage

/// `CodeCoverage.CoverageProcessor` is the LLVM-side gather/parse driver
/// shipped by `swift-code-coverage`. It collides by name with the new
/// OTel-style `EventsExporter.CoverageProcessor` protocol. Define this
/// alias in a file that doesn't import `EventsExporter` so the original
/// name stays unambiguous here; everywhere else we use
/// `LLVMCoverageProcessor`.
typealias LLVMCoverageProcessor = CoverageProcessor
