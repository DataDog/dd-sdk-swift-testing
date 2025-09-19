/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

final class RetryAndSkipTags: TestHooksFeature {
    static let id: FeatureId = "Add Retry and Skip Tags"
    
    func testWillStart(test: any TestRun, info: TestRunInfoStart) {
        if let retry = info.retry {
            test.set(tag: DDEfdTags.testIsRetry, value: "true")
            test.set(tag: DDEfdTags.testRetryReason, value: retry.reason)
        }
    }
    
    func testWillFinish(test: any TestRun, duration: TimeInterval,
                        withStatus status: TestStatus, andInfo info: TestRunInfoEnd)
    {
        if status == .skip, let skip = info.skip.by {
            test.set(tag: DDTestTags.testSkipReason, value: skip.reason)
        }
        if info.executions.total > 0 && !info.retry.status.isRetry {
            // This was a retry and retries are finished
            if info.executions.failed >= info.executions.total && status == .fail {
                // last execution and all previous executions failed
                test.set(tag: DDTestTags.testHasFailedAllRetries, value: "true")
            }
        }
    }
    
    func stop() {}
}
