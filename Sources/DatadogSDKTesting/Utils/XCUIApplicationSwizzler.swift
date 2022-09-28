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
        DDTestMonitor.instance?.currentTest?.setIsUITest(true)
        if let testSpanContext = DDTracer.activeSpan?.context {
            self.launchEnvironment["ENVIRONMENT_TRACER_SPANID"] = testSpanContext.spanId.hexString
            self.launchEnvironment["ENVIRONMENT_TRACER_TRACEID"] = testSpanContext.traceId.hexString
            addPropagationsHeadersToEnvironment(tracer: DDTestMonitor.tracer)
            for value in ConfigurationValues.allCases {
                addProcessEnvironmentToLaunch(value.rawValue)
            }
        }
        DDTestMonitor.instance?.startAttributeListener()
        swizzled_launch()
    }
}
