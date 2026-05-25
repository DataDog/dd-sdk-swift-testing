/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

// MARK: - Coverage context

/// Identifies which test / suite a coverage payload belongs to. Shared
/// between the unprocessed `CoverageRecord` (URL form) and the processed
/// `CoverageData` so the processor pipeline doesn't need to translate it.
public enum CoverageContext: Sendable {
    case test(testSpanId: SpanId, suiteId: SpanId, sessionId: SpanId)
    case suite(suiteSpanId: SpanId, sessionId: SpanId)

    public var sessionId: SpanId {
        switch self {
        case .test(_, _, let id), .suite(_, let id): return id
        }
    }

    public var suiteId: SpanId {
        switch self {
        case .test(_, let id, _): return id
        case .suite(let id, _): return id
        }
    }

    public var testId: SpanId? {
        switch self {
        case .test(let id, _, _): return id
        case .suite: return nil
        }
    }

    public var isSuite: Bool {
        if case .suite = self { return true }
        return false
    }
}

// MARK: - Per-file coverage entry

/// A single file's coverage payload, in wire-ready shape: the absolute
/// path (workspace stripping happens inside the exporter) and a
/// bit-per-line coverage mask. Built by the `CoverageProcessor`
/// implementation from whatever parser the SDK is using.
public struct CoverageFile: Sendable {
    public let name: String
    public let bitmap: Data

    public init(name: String, bitmap: Data) {
        self.name = name
        self.bitmap = bitmap
    }
}

// MARK: - Processed coverage payload

/// The processed coverage payload ready for the exporter. Produced by
/// `CoverageProcessor.onEnd(record:)` from a URL-based `CoverageRecord`
/// — analogous to `ReadableLogRecord` / `SpanData`, the immutable,
/// fully-formed object the OTel-style coverage exporter consumes.
public struct CoverageData {
    public let name: String
    public let files: [CoverageFile]
    public let resource: Resource
    public let instrumentationScopeInfo: InstrumentationScopeInfo
    public let context: CoverageContext
    public let workspacePath: URL?

    public init(name: String,
                files: [CoverageFile],
                workspacePath: URL?,
                resource: Resource,
                instrumentationScopeInfo: InstrumentationScopeInfo,
                context: CoverageContext)
    {
        self.name = name
        self.files = files
        self.workspacePath = workspacePath
        self.resource = resource
        self.instrumentationScopeInfo = instrumentationScopeInfo
        self.context = context
    }
}

// MARK: - Unprocessed coverage record (URL form)

/// What the SDK (`CodeCoverageProvider`) hands to a `CoverageProcessor`
/// when a test ends: a pointer to the raw profraw file plus the OTel
/// anchors. The processor parses the file, builds `CoverageData`, and
/// passes it to a `CoverageExporterType`.
public struct CoverageRecord {
    public let name: String
    /// URL of the profraw / profdata file produced by LLVM. The processor
    /// owns the lifetime — it parses this file synchronously on
    /// `onEnd(record:)` and may delete or retain it after.
    public let coverageFileURL: URL
    public let resource: Resource
    public let instrumentationScopeInfo: InstrumentationScopeInfo
    public let context: CoverageContext
    public let workspacePath: URL?

    public init(name: String,
                coverageFileURL: URL,
                workspacePath: URL?,
                resource: Resource,
                instrumentationScopeInfo: InstrumentationScopeInfo,
                context: CoverageContext)
    {
        self.name = name
        self.coverageFileURL = coverageFileURL
        self.workspacePath = workspacePath
        self.resource = resource
        self.instrumentationScopeInfo = instrumentationScopeInfo
        self.context = context
    }
}
