/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
@_implementationOnly import XCTest

extension XCUIApplication {
    static let swizzleMethods: Void = {
        guard let originalMethod = class_getInstanceMethod(XCUIApplication.self, #selector(launch)),
        let swizzledMethod = class_getInstanceMethod(XCUIApplication.self, #selector(swizzled_launch))
        else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    @objc
    func swizzled_launch() {
        if let testSpanContext = DDTestMonitor.instance?.tracer.activeTestSpan?.context {
            self.launchEnvironment["DD_TEST_RUNNER"] = "1"
            self.launchEnvironment["DATADOG_CLIENT_TOKEN"] = ProcessInfo.processInfo.environment["DATADOG_CLIENT_TOKEN"]
            self.launchEnvironment["XCTestConfigurationFilePath"] = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]
            self.launchEnvironment["ENVIRONMENT_TRACER_SPANID"] = testSpanContext.spanId.hexString
            self.launchEnvironment["ENVIRONMENT_TRACER_TRACEID"] = testSpanContext.traceId.hexString
            self.launchEnvironment["DD_ENV"] = ProcessInfo.processInfo.environment["DD_ENV"]
            self.launchEnvironment["DD_SERVICE"] = ProcessInfo.processInfo.environment["DD_SERVICE"]
            self.launchEnvironment["DD_DISABLE_NETWORK_INSTRUMENTATION"] = ProcessInfo.processInfo.environment["DD_DISABLE_NETWORK_INSTRUMENTATION"]
            self.launchEnvironment["DD_DISABLE_HEADERS_INJECTION"] = ProcessInfo.processInfo.environment["DD_DISABLE_HEADERS_INJECTION"]
            self.launchEnvironment["DD_DISABLE_STDOUT_INSTRUMENTATION"] = ProcessInfo.processInfo.environment["DD_DISABLE_STDOUT_INSTRUMENTATION"]
            self.launchEnvironment["DD_DISABLE_STDERR_INSTRUMENTATION"] = ProcessInfo.processInfo.environment["DD_DISABLE_STDERR_INSTRUMENTATION"]
        }
        swizzled_launch()
    }
}
