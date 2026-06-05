/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

struct SessionAndModuleObserver: TestSessionManagerObserver, TestModuleManagerObserver {
    func didStart(session: any TestSession) async {
        session.configuration.activeFeatures.testSessionWillStart(session: session)
    }

    func willFinish(session: any TestSession) async {
        session.configuration.activeFeatures.testSessionWillEnd(session: session)
    }

    func didFinish(session: any TestSession) async {
        session.configuration.activeFeatures.testSessionDidEnd(session: session)
        #if canImport(Testing)
            DatadogSwiftTestingTrait.sharedSuiteProvider = nil
        #endif
    }

    func didStart(module: any TestModule) {
        DDCrashes.setCurrent(spanData: module.toCrashData)
        module.configuration.activeFeatures.testModuleWillStart(module: module)
    }

    func willFinish(module: any TestModule) {
        module.configuration.activeFeatures.testModuleWillEnd(module: module)
    }

    func didFinish(module: any TestModule) {
        DDCrashes.setCurrent(spanData: nil)
        module.configuration.activeFeatures.testModuleDidEnd(module: module)
    }
}
