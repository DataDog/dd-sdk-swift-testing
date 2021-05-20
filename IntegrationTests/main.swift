/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import XCTest
import OpenTelemetrySdk

guard let testClass = ProcessInfo.processInfo.environment["TEST_CLASS"],
      let outputPath = ProcessInfo.processInfo.environment["TEST_OUTPUT_FILE"],
      let theClass: AnyClass = Bundle.main.classNamed(testClass)
else {
    print("No test class passed")
    exit(1)
}

//Create a exporter to export the spans to the desired file
let exporter = FileTraceExporter(outputURL:  URL(fileURLWithPath: outputPath))
OpenTelemetrySDK.instance.tracerProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))

// Force a testBundleWillStart using the app bundle
let observer = (XCTestObservationCenter.shared.value(forKey: "_observers") as! NSMutableArray).lastObject as! XCTestObservation
let currentBundleName = Bundle.main.bundleURL.deletingPathExtension().lastPathComponent
observer.testBundleWillStart?(Bundle.main)

//Run the desised test
let testSuite = XCTestSuite(forTestCaseClass: theClass)
testSuite.run()

//Force flushing the results
OpenTelemetrySDK.instance.tracerProvider.forceFlush()


//Start the app in the standard way so all events are launched. It will be closed just after starting
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
