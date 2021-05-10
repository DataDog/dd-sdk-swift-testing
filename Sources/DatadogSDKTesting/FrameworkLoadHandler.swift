/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

public class FrameworkLoadHandler: NSObject {
    static var environment = ProcessInfo.processInfo.environment

    @objc
    public static func handleLoad() {
        installTestObserver()
    }

    internal static func installTestObserver() {
        /// Only initialize test observer if user configured so and is running tests
        guard environment["DD_TEST_RUNNER"] != nil else {
            return
        }

        let isInTestMode = environment["XCInjectBundleInto"] != nil ||
            environment["XCTestConfigurationFilePath"] != nil
        if isInTestMode {
            DDTestMonitor.instance = DDTestMonitor()
            DDTestMonitor.instance?.startInstrumenting()
        }
    }
}
