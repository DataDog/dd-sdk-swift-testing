/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// Typed tag values for the CI Visibility telemetry metrics.
///
/// Each `rawValue` is the exact string the intake expects, so callers pick a
/// case (`.testCycle`) instead of remembering a string (`"test_cycle"`). Tags
/// whose value set is open-ended or language-specific (test framework, coverage
/// library, CI provider, browser driver) stay plain `String` on the metric APIs.
extension Telemetry {
    /// `event_type` — the lifecycle level an event belongs to.
    enum EventType: String, SpanAttributeConvertible {
        case test, suite, module, session
    }

    /// `endpoint` — which intake endpoint a payload targets.
    enum Endpoint: String, SpanAttributeConvertible {
        case testCycle = "test_cycle"
        case codeCoverage = "code_coverage"
    }

    /// `error_type` — why a backend request failed.
    enum ErrorType: String, SpanAttributeConvertible {
        case timeout
        case network
        case statusCode4xx = "status_code_4xx_response"
        case statusCode5xx = "status_code_5xx_response"
    }

    /// `command` — the git operation a metric refers to.
    enum GitCommand: String, SpanAttributeConvertible {
        case getRepository = "get_repository"
        case getBranch = "get_branch"
        case checkShallow = "check_shallow"
        case unshallow
        case getLocalCommits = "get_local_commits"
        case getObjects = "get_objects"
        case packObjects = "pack_objects"
    }

    /// `retry_reason` — why a test was retried.
    enum RetryReason: String, SpanAttributeConvertible {
        case earlyFlakeDetection = "efd"
        case autoTestRetry = "atr"
    }

    /// `early_flake_detection_abort_reason` — why EFD was not applied.
    enum EFDAbortReason: String, SpanAttributeConvertible {
        case slow
    }

    /// `expected_provider` / `discrepant_provider` — source of a git value when
    /// reporting commit-SHA discrepancies.
    enum ShaProvider: String, SpanAttributeConvertible {
        case userSupplied = "user_supplied"
        case ciProvider = "ci_provider"
        case localGit = "local_git"
        case gitClient = "git_client"
        case embedded
    }

    /// `type` — the kind of commit-SHA discrepancy found.
    enum ShaDiscrepancyType: String, SpanAttributeConvertible {
        case repository = "repository_discrepancy"
        case commit = "commit_discrepancy"
    }
}
