/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
@_implementationOnly import XCTest

extension XCUIApplication {
    fileprivate func addProcessEnvironmentToLaunch(_ environment: String) {
        self.launchEnvironment[environment] = ProcessInfo.processInfo.environment[environment]
    }

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
            self.launchEnvironment["ENVIRONMENT_TRACER_SPANID"] = testSpanContext.spanId.hexString
            self.launchEnvironment["ENVIRONMENT_TRACER_TRACEID"] = testSpanContext.traceId.hexString
            [
                "DATADOG_CLIENT_TOKEN",
                "XCTestConfigurationFilePath",
                "DD_ENV",
                "DD_SERVICE",
                "DD_DISABLE_NETWORK_INSTRUMENTATION",
                "DD_DISABLE_HEADERS_INJECTION",
                "DD_DISABLE_STDOUT_INSTRUMENTATION",
                "DD_DISABLE_STDERR_INSTRUMENTATION"
            ].forEach( addProcessEnvironmentToLaunch )
        }
        swizzled_launch()
    }
}
