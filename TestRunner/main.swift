/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import XCTest
import OpenTelemetrySdk

guard let testClass = ProcessInfo.processInfo.environment["TEST_CLASS"],
      let theClass: AnyClass = Bundle.main.classNamed(testClass)
else {
    print("No test class passed")
    exit(1)
}

let testSuite = XCTestSuite(forTestCaseClass: theClass)
testSuite.run()
OpenTelemetrySDK.instance.tracerProvider.forceFlush()


#if os(macOS)
import Cocoa
let app = NSApplicationMain(CommandLine.argc,
                            CommandLine.unsafeArgv)

#else
import UIKit
UIApplicationMain(CommandLine.argc,
                  CommandLine.unsafeArgv,
                  nil,
                  nil)
#endif
