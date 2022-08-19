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

    var module: DDTestModule?
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
        module = DDTestModule.start(bundleName: bundleName)
        module?.testFramework = "XCTest"
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        /// We need to wait for all the traces to be written to the backend before exiting
        module?.end()
    }

    func testSuiteWillStart(_ testSuite: XCTestSuite) {
        if module?.configError ?? false {
            testSuite.testRun?.stop()
            exit(1)
        }

        guard let tests = testSuite.value(forKey: "_mutableTests") as? NSArray,
              tests.firstObject is XCTestCase,
              let module = module
        else {
            return
        }

        if let itr = module.itr {
            let skippableTests = itr.skippableTests.filter { $0.suite == testSuite.name }.map { "-[\(testSuite.name) \($0.name)]" }
            let finalTests = tests.filter { !skippableTests.contains(($0 as AnyObject).name) }
            Log.print("ITR skipped \(tests.count - finalTests.count) tests")
            testSuite.setValue(finalTests, forKey: "_mutableTests")
            if !finalTests.isEmpty {
                suite = module.suiteStart(name: testSuite.name)
            }
        } else {
            suite = module.suiteStart(name: testSuite.name)
        }
    }

    func testSuiteDidFinish(_ testSuite: XCTestSuite) {
        if let tests = testSuite.value(forKey: "_mutableTests") as? NSArray,
           tests.firstObject is XCTestCase
        {
            suite?.end()
        }
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        guard let suite = suite,
              let namematch = DDTestObserver.testNameRegex.firstMatch(in: testCase.name, range: NSRange(location: 0, length: testCase.name.count)),
              let nameRange = Range(namematch.range(at: 2), in: testCase.name)
        else {
            return
        }
        let testName = String(testCase.name[nameRange])
        test = suite.testStart(name: testName)
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        guard let test = test
        else {
            return
        }
        addBenchmarkTagsIfNeeded(testCase: testCase, test: test)

        if DDTestObserver.supportsSkipping, testCase.testRun?.hasBeenSkipped == true {
            test.end(status: .skip)
        } else if testCase.testRun?.hasSucceeded ?? false {
            test.end(status: .pass)
        } else {
            test.end(status: .fail)
        }
    }

    #if swift(>=5.3)
    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        guard let test = test
        else {
            return
        }
        test.setErrorInfo(type: issue.compactDescription, message: issue.description, callstack: nil)
    }
    #else
    func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {
        guard let test = test
        else {
            return
        }
        test.setErrorInfo(type: description, message: "test_failure: \(filePath ?? ""):\(lineNumber)", callstack: nil)
    }
    #endif

    fileprivate func measurements(_ metric: AnyObject) -> [Double]? {
        let measurements = metric.value(forKey: "measurements") as? [Double]
        if let measurements = measurements,
           !measurements.isEmpty
        {
            return measurements
        }
        return nil
    }

    private func addBenchmarkTagsIfNeeded(testCase: XCTestCase, test: DDTest) {
        guard let metrics = testCase.value(forKey: "_perfMetricsForID") as? [XCTPerformanceMetric: AnyObject] else {
            return
        }

        metrics.forEach { metric in
            guard let measurements = measurements(metric.value) else {
                return
            }
            let info = metric.value.value(forKey: "_name") as? String
            let samples: [Double]
            let name: String
            switch metric.key {
                case XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_TotalHeapAllocationsKilobytes"):
                    samples = measurements.map { $0 * 1024 } // Convert to bytes
                    name = DDBenchmarkMeasuresTags.total_heap_allocations
                case XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_PersistentVMAllocations"):
                    samples = measurements.map { $0 * 1024 } // Convert to bytes
                    name = DDBenchmarkMeasuresTags.persistent_vm_allocations
                case XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_RunTime"):
                    samples = measurements.map { $0 * 1000000000 } // Convert to nanoseconds
                    name = DDBenchmarkMeasuresTags.run_time
                case XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_PersistentHeapAllocations"):
                    samples = measurements.map { $0 * 1024 } // Convert to bytes
                    name = DDBenchmarkMeasuresTags.persistent_heap_allocations
                case XCTPerformanceMetric(rawValue: "com.apple.dt.XCTMetric_Memory.physical"):
                    samples = measurements.map { $0 * 1024 } // Convert to bytes
                    name = DDBenchmarkMeasuresTags.memory_physical
                case XCTPerformanceMetric(rawValue: "com.apple.dt.XCTMetric_CPU.instructions_retired"):
                    samples = measurements.map { $0 * 1000 } // Convert to instructions
                    name = DDBenchmarkMeasuresTags.cpu_instructions_retired
                case XCTPerformanceMetric(rawValue: "com.apple.dt.XCTMetric_CPU.cycles"):
                    samples = measurements
                    name = DDBenchmarkMeasuresTags.cpu_cycles
                case XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_TemporaryHeapAllocationsKilobytes"):
                    samples = measurements.map { $0 * 1024 }
                    name = DDBenchmarkMeasuresTags.temporary_heap_allocations
                case XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_HighWaterMarkForVMAllocations"):
                    samples = measurements.map { $0 * 1024 }
                    name = DDBenchmarkMeasuresTags.high_water_mark_vm_allocations
                case XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_TransientHeapAllocationsKilobytes"):
                    samples = measurements.map { $0 * 1024 }
                    name = DDBenchmarkMeasuresTags.transient_heap_allocations
                case XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_TransientVMAllocationsKilobytes"):
                    samples = measurements.map { $0 * 1024 }
                    name = DDBenchmarkMeasuresTags.transient_heap_allocations
                case XCTPerformanceMetric(rawValue: "com.apple.dt.XCTMetric_Memory.physical_peak"):
                    samples = measurements.map { $0 * 1024 }
                    name = DDBenchmarkMeasuresTags.memory_physical_peak
                case XCTPerformanceMetric(rawValue: "com.apple.dt.XCTMetric_CPU.time"):
                    samples = measurements.map { $0 * 1000000000 }
                    name = DDBenchmarkMeasuresTags.cpu_time
                case XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_UserTime"):
                    samples = measurements.map { $0 * 1000000000 }
                    name = DDBenchmarkMeasuresTags.user_time
                case XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_HighWaterMarkForHeapAllocations"):
                    samples = measurements.map { $0 * 1024 }
                    name = DDBenchmarkMeasuresTags.high_water_mark_heap_allocations
                case XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_SystemTime"):
                    samples = measurements.map { $0 * 1000000000 } // Convert to nanoseconds
                    name = DDBenchmarkMeasuresTags.system_time
                case XCTPerformanceMetric(rawValue: "com.apple.dt.XCTMetric_Clock.time.monotonic"):
                    samples = measurements.map { $0 * 1000000000 } // Convert to nanoseconds
                    name = DDBenchmarkMeasuresTags.clock_time_monotonic
                case XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_TransientHeapAllocationsNodes"):
                    samples = measurements
                    name = DDBenchmarkMeasuresTags.transient_heap_allocations_nodes
                case XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_PersistentHeapAllocationsNodes"):
                    samples = measurements
                    name = DDBenchmarkMeasuresTags.persistent_heap_allocations_nodes
                case XCTPerformanceMetric(rawValue: "com.apple.dt.XCTMetric_Disk.logical_writes"):
                    samples = measurements.map { $0 * 1024 }
                    name = DDBenchmarkMeasuresTags.disk_logical_writes
                case XCTPerformanceMetric(rawValue: "com.apple.XCTPerformanceMetric_WallClockTime"):
                    samples = measurements.map { $0 * 1000000000 } // Convert to nanoseconds
                    name = DDBenchmarkMeasuresTags.duration
                case XCTPerformanceMetric(rawValue: "com.apple.dt.XCTMetric_ApplicationLaunch-AppLaunch.duration"):
                    samples = measurements.map { $0 * 1000000000 } // Convert to nanoseconds
                    name = DDBenchmarkMeasuresTags.application_launch
                default:
                    samples = measurements
                    name = info ?? "unknown_measure"
            }
            test.addBenchmark(name: name, samples: samples, info: info)
        }
    }
}
