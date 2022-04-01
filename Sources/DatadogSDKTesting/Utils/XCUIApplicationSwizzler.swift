/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
@_implementationOnly import XCTest

extension XCUIApplication {
    fileprivate func addProcessEnvironmentToLaunch(_ environment: String) {
        self.launchEnvironment[environment] = DDEnvironmentValues.getEnvVariable(environment)
    }

    fileprivate func addPropagationsHeadersToEnvironment(tracer: DDTracer?) {
        if let headers = tracer?.environmentPropagationHTTPHeaders() {
            self.launchEnvironment.merge(headers) { _, new in new }
        }
    }

    static let swizzleMethods: Void = {
        guard let originalMethod = class_getInstanceMethod(XCUIApplication.self, #selector(launch)),
              let swizzledMethod = class_getInstanceMethod(XCUIApplication.self, #selector(swizzled_launch))
        else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    @objc
    func swizzled_launch() {
        DDTracer.activeSpan?.setAttribute(key: DDTestTags.testIsUITest, value: "true")
        if let testSpanContext = DDTracer.activeSpan?.context {
            self.launchEnvironment["ENVIRONMENT_TRACER_SPANID"] = testSpanContext.spanId.hexString
            self.launchEnvironment["ENVIRONMENT_TRACER_TRACEID"] = testSpanContext.traceId.hexString
            addPropagationsHeadersToEnvironment(tracer: DDTestMonitor.tracer)
            [
                "DD_TEST_RUNNER",
                "DATADOG_CLIENT_TOKEN",
                "DD_API_KEY",
                "XCTestConfigurationFilePath",
                "XCInjectBundleInto",
                "XCTestBundlePath",
                "SDKROOT",
                "DD_ENV",
                "DD_SERVICE",
                "SRCROOT",
                "DD_TAGS",
                "DD_DISABLE_NETWORK_INSTRUMENTATION",
                "DD_DISABLE_HEADERS_INJECTION",
                "DD_INSTRUMENTATION_EXTRA_HEADERS",
                "DD_EXCLUDED_URLS",
                "DD_ENABLE_RECORD_PAYLOAD",
                "DD_MAX_PAYLOAD_SIZE",
                "DD_ENABLE_STDOUT_INSTRUMENTATION",
                "DD_ENABLE_STDERR_INSTRUMENTATION",
                "DD_DISABLE_SDKIOS_INTEGRATION",
                "DD_DISABLE_CRASH_HANDLER",
                "DD_SITE",
                "DD_ENDPOINT",
                "DD_DONT_EXPORT",
                "DD_DISABLE_NETWORK_CALL_STACK",
                "DD_ENABLE_NETWORK_CALL_STACK_SYMBOLICATED",
            ].forEach(addProcessEnvironmentToLaunch)
        }
        DDTestMonitor.instance?.startAttributeListener()
        swizzled_launch()
    }
}
