/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
@_implementationOnly import XCTest

class DDTestObserver: NSObject, XCTestObservation {
    static let testNameRegex = try! NSRegularExpression(pattern: "([\\w]+) ([\\w]+)", options: .caseInsensitive)
    static let supportsSkipping = NSClassFromString("XCTSkippedTestContext") != nil
    static let tracerVersion = (Bundle(for: DDTestObserver.self).infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"

    var session: DDTestSession?
    var suite: DDTestSuite?
    var test: DDTest?

    override init() {
        XCUIApplication.swizzleMethods
        super.init()
    }

    func startObserving() {
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        let bundleName = testBundle.bundleURL.deletingPathExtension().lastPathComponent
        session = DDTestSession(bundleName: bundleName)
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        /// We need to wait for all the traces to be written to the backend before exiting
        session?.end()
    }

    func testSuiteWillStart(_ testSuite: XCTestSuite) {
        suite = session?.suiteStart(name: testSuite.name)
    }

    func testSuiteDidFinish(_ testSuite: XCTestSuite) {
        if let suite = suite {
            session?.suiteEnd(suite: suite)
        }
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        guard let session = session,
              let suite = suite,
              let namematch = DDTestObserver.testNameRegex.firstMatch(in: testCase.name, range: NSRange(location: 0, length: testCase.name.count)),
              let nameRange = Range(namematch.range(at: 2), in: testCase.name)
        else {
            return
        }
        let testName = String(testCase.name[nameRange])

        test = session.testStart(name: testName, suite: suite)
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        guard let session = session,
              let test = test
        else {
            return
        }
        addBenchmarkTagsIfNeeded(testCase: testCase, test: test)

        if DDTestObserver.supportsSkipping, testCase.testRun?.hasBeenSkipped == true {
            session.testEnd(test: test, status: .skip)
        } else if testCase.testRun?.hasSucceeded ?? false {
            session.testEnd(test: test, status: .pass)
        } else {
            session.testEnd(test: test, status: .fail)
        }
    }

    #if swift(>=5.3)
    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        guard let session = session,
              let test = test
        else {
            return
        }
        session.testSetErrorInfo(test: test, type: issue.compactDescription, message: issue.description, callstack: issue.detailedDescription)
    }
    #else
    func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {
        guard let session = session,
              let test = test
        else {
            return
        }
        session.testSetErrorInfo(test: test, type: description, message: "test_failure: \(filePath ?? ""):\(lineNumber)", callstack: nil)
    }
    #endif

    private func addBenchmarkTagsIfNeeded(testCase: XCTestCase, test: DDTest) {
        guard let metrics = testCase.value(forKey: "_perfMetricsForID") as? [XCTPerformanceMetric: AnyObject] else {
            return
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_TotalHeapAllocationsKilobytes")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1024 } // Convert to bytes
            test.addBenchmark(name: DDBenchmarkMeasuresTags.total_heap_allocations, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_PersistentVMAllocations")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1024 } // Convert to bytes
            test.addBenchmark(name: DDBenchmarkMeasuresTags.persistent_vm_allocations, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_RunTime")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1000000000 } // Convert to nanoseconds
            test.addBenchmark(name: DDBenchmarkMeasuresTags.run_time, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_PersistentHeapAllocations")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1024 } // Convert to bytes
            test.addBenchmark(name: DDBenchmarkMeasuresTags.persistent_heap_allocations, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.dt.XCTMetric_Memory.physical")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1024 } // Convert to bytes
            test.addBenchmark(name: DDBenchmarkMeasuresTags.memory_physical, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.dt.XCTMetric_CPU.instructions_retired")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1000 } // Convert to instructions
            test.addBenchmark(name: DDBenchmarkMeasuresTags.cpu_instructions_retired, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.dt.XCTMetric_CPU.cycles")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            test.addBenchmark(name: DDBenchmarkMeasuresTags.cpu_cycles, samples: measurements, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_TemporaryHeapAllocationsKilobytes")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1024 } // Convert to bytes
            test.addBenchmark(name: DDBenchmarkMeasuresTags.temporary_heap_allocations, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_HighWaterMarkForVMAllocations")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1024 } // Convert to bytes
            test.addBenchmark(name: DDBenchmarkMeasuresTags.high_water_mark_vm_allocations, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_TransientHeapAllocationsKilobytes")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1024 } // Convert to bytes
            test.addBenchmark(name: DDBenchmarkMeasuresTags.transient_heap_allocations, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "XCTPerformanceMetric_TransientVMAllocationsKilobytes")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1024 } // Convert to bytes
            test.addBenchmark(name: DDBenchmarkMeasuresTags.transient_vm_allocations, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.dt.XCTMetric_Memory.physical_peak")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1024 } // Convert to bytes
            test.addBenchmark(name: DDBenchmarkMeasuresTags.memory_physical_peak, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.dt.XCTMetric_CPU.time")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1000000000 } // Convert to nanoseconds
            test.addBenchmark(name: DDBenchmarkMeasuresTags.cpu_time, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_UserTime")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1000000000 } // Convert to nanoseconds
            test.addBenchmark(name: DDBenchmarkMeasuresTags.user_time, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_HighWaterMarkForHeapAllocations")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1024 } // Convert to bytes
            test.addBenchmark(name: DDBenchmarkMeasuresTags.high_water_mark_heap_allocations, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_SystemTime")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1000000000 } // Convert to nanoseconds
            test.addBenchmark(name: DDBenchmarkMeasuresTags.system_time, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.dt.XCTMetric_Clock.time.monotonic")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1000000000 } // Convert to nanoseconds
            test.addBenchmark(name: DDBenchmarkMeasuresTags.clock_time_monotonic, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_TransientHeapAllocationsNodes")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            test.addBenchmark(name: DDBenchmarkMeasuresTags.transient_heap_allocations_nodes, samples: measurements, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_PersistentHeapAllocationsNodes")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1024 }
            test.addBenchmark(name: DDBenchmarkMeasuresTags.persistent_heap_allocations_nodes, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.dt.XCTMetric_Disk.logical_writes")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1024 }
            test.addBenchmark(name: DDBenchmarkMeasuresTags.disk_logical_writes, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_WallClockTime")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1000000000 } // Convert to nanoseconds
            test.addBenchmark(name: DDBenchmarkMeasuresTags.duration, samples: values, info: metric.value(forKey: "_name") as? String)
        }
        if let metric = metrics[XCTPerformanceMetric(rawValue: "com.apple.dt.XCTMetric_ApplicationLaunch-AppLaunch.duration")],
           let measurements = metric.value(forKey: "measurements") as? [Double],
           measurements.count > 0
        {
            let values = measurements.map { $0 * 1000000000 } // Convert to nanoseconds
            test.addBenchmark(name: DDBenchmarkMeasuresTags.application_launch, samples: values, info: metric.value(forKey: "_name") as? String)
        }
    }
}
