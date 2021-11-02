/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

@_implementationOnly import OpenTelemetrySdk
import XCTest


guard let outputPath = ProcessInfo.processInfo.environment["TEST_OUTPUT_FILE"] else {
    exit(0)
}
// Create a exporter to export the spans to the desired file
let exporter = FileTraceExporter(outputURL: URL(fileURLWithPath: outputPath))

OpenTelemetrySDK.instance.tracerProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))

if let testClass = ProcessInfo.processInfo.environment["TEST_CLASS"],
   let theClass: AnyClass = Bundle.main.classNamed(testClass)
{
    // Force a testBundleWillStart using the app bundle
    let observer = (XCTestObservationCenter.shared.value(forKey: "_observers") as! NSMutableArray).lastObject as! XCTestObservation
   // let currentBundleName = Bundle.main.bundleURL.deletingPathExtension().lastPathComponent
    observer.testBundleWillStart?(Bundle.main)

    // Run the desired test
    let testSuite = XCTestSuite(forTestCaseClass: theClass)
    testSuite.run()

    // Force flushing the results
    OpenTelemetrySDK.instance.tracerProvider.forceFlush()
    startApp()
}
else {
    createNetworkRequest()
    OpenTelemetrySDK.instance.tracerProvider.forceFlush()
    startApp()
}

// Start the app in the standard way so all events are launched. It will be closed just after starting
#if os(macOS)
import Cocoa
func startApp() {
    _ = NSApplicationMain(CommandLine.argc,
                          CommandLine.unsafeArgv)
}
#else
import UIKit
func startApp() {
    UIApplicationMain(CommandLine.argc,
                      CommandLine.unsafeArgv,
                      nil,
                      nil)
}
#endif

// Simple network request that we will validate is generated in the test output
func createNetworkRequest() {
    let url = URL(string: "http://httpbin.org/get")!
    let request = URLRequest(url: url)
    let semaphore = DispatchSemaphore(value: 0)

    let task = URLSession.shared.dataTask(with: request) { data, _, _ in
        if let data = data {
            let string = String(data: data, encoding: .utf8)
            print(string ?? "")
        }
        semaphore.signal()
    }
    task.resume()
    semaphore.wait()
}
