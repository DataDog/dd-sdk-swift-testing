/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

struct SessionAndModuleObserver: TestSessionManagerObserver, TestModuleManagerObserver {
    func didStart(session: any TestSession, with config: SessionConfig) async {
        config.activeFeatures.testSessionWillStart(session: session)
    }
    
    func willFinish(session: any TestSession, with config: SessionConfig) async {
        config.activeFeatures.testSessionWillEnd(session: session)
    }
    
    func didFinish(session: any TestSession, with config: SessionConfig) async {
        config.activeFeatures.testSessionDidEnd(session: session)
        #if canImport(Testing)
            DatadogSwiftTestingTrait.sharedSuiteProvider = nil
        #endif
    }
    
    func didStart(module: any TestModule, with config: SessionConfig) {
        DDCrashes.setCurrent(spanData: module.toCrashData)
        config.activeFeatures.testModuleWillStart(module: module)
    }
    
    func willFinish(module: any TestModule, with config: SessionConfig) {
        config.activeFeatures.testModuleWillEnd(module: module)
    }
    
    func didFinish(module: any TestModule, with config: SessionConfig) {
        DDCrashes.setCurrent(spanData: nil)
        config.activeFeatures.testModuleDidEnd(module: module)
    }
}
