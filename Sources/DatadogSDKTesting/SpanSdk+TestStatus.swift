/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@preconcurrency internal import OpenTelemetryApi
@preconcurrency internal import OpenTelemetrySdk

/// `TestStatus` <-> `SpanSdk` plumbing shared by `Test` / `Session` /
/// `Module` / `Suite`. Each test-model object stores its status in the
/// `DDTestTags.testStatus` attribute and mirrors the failed/passed split
/// onto `span.status`. Reading goes to the tag first and falls back to
/// `span.status`, so externally-set error states still surface.
extension SpanSdk {
    /// Resolve the logical `TestStatus`. Tag wins; if absent (e.g. the
    /// span only has its OTel status set), derive from `span.status`.
    var testStatus: TestStatus {
        if let value = getAttributes()[DDTestTags.testStatus]?.description,
           let parsed = TestStatus(spanAttribute: value)
        {
            return parsed
        }
        return self.status.isError ? .fail : .pass
    }

    /// Apply `status` to the span: writes `DDTestTags.testStatus` and
    /// unconditionally overwrites `span.status` to match. When moving
    /// out of `.fail` we also clear the `error.*` attribute tags so the
    /// payload doesn't carry stale error info. Callers that want to
    /// preserve an existing status across an end-of-life finalization
    /// step should do a get-then-set round-trip through `testStatus`.
    func applyStatus(_ status: TestStatus, errorDescription: @autoclosure () -> String) {
        setAttribute(key: DDTestTags.testStatus, value: .string(status.spanAttribute))
        switch status {
        case .fail:
            self.status = .error(description: errorDescription())
        case .pass, .skip:
            let wasError = self.status.isError
            self.status = .ok
            if wasError {
                clearErrorTags()
            }
        }
    }

    /// Drop every `error.*` attribute (including the indexed
    /// `error.crash_log.NN` keys). Called when transitioning out of a
    /// failed status so the payload doesn't carry stale error info.
    private func clearErrorTags() {
        let toRemove = getAttributes().keys.filter { $0.hasPrefix("error.") }
        for key in toRemove {
            setAttribute(key: key, value: nil)
        }
    }
}
