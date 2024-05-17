/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import XCTest

class DDTestObserver: NSObject, XCTestObservation {
    static let testNameRegex = try! NSRegularExpression(pattern: "([\\w]+) ([\\w]+)", options: .caseInsensitive)
    static let tracerVersion = (Bundle(for: DDTestObserver.self).infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
    
    enum State {
        case none
        case module(DDTestModule)
        case container(suite: ContainerSuite, inside: DDTestModule)
        case suite(suite: DDTestSuite, inside: ContainerSuite?)
        case test(test: DDTest, inside: ContainerSuite?)
    }
    
    indirect enum ContainerSuite {
        case simple(XCTestSuite)
        case nested(XCTestSuite, parent: ContainerSuite)
        
        var suite: XCTestSuite {
            switch self {
            case .simple(let s): return s
            case .nested(let s, parent: _): return s
            }
        }
        
        var parent: ContainerSuite? {
            switch self {
            case .nested(_, parent: let p): return p
            case .simple(_): return nil
            }
        }
        
        init(suite: XCTestSuite, parent: ContainerSuite? = nil) {
            if let parent = parent {
                self = .nested(suite, parent: parent)
            } else {
                self = .simple(suite)
            }
        }
    }

    private(set) var state: State

    override init() {
        XCUIApplication.swizzleMethods
        state = .none
        super.init()
    }

    func startObserving() {
        XCTestObservationCenter.shared.addTestObserver(self)
    }
    
    func stopObserving() {
        XCTestObservationCenter.shared.removeTestObserver(self)
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        guard case .none = state else {
            Log.print("testBundleWillStart: Bad observer state: \(state), expected: .none")
            return
        }
        let bundleName = testBundle.name
        Log.debug("testBundleWillStart: \(bundleName)")
        let module = DDTestModule.start(bundleName: bundleName)
        module.testFramework = "XCTest"
        state = .module(module)
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        guard case .module(let module) = state else {
            Log.print("testBundleDidFinish: Bad observer state: \(state), expected: .module")
            return
        }
        guard module.bundleName == testBundle.name else {
            Log.print("testBundleDidFinish: Bad module: \(testBundle.name), expected: \(module.bundleName)")
            state = .none
            return
        }
        /// We need to wait for all the traces to be written to the backend before exiting
        module.end()
        state = .none
        Log.debug("testBundleDidFinish: \(module.bundleName)")
    }

    func testSuiteWillStart(_ testSuite: XCTestSuite) {
        let module: DDTestModule
        let parent: ContainerSuite?
        
        switch state {
        case .module(let mod):
            module = mod
            parent = nil
        case .container(suite: let cont, inside: let mod):
            module = mod
            parent = cont
        default:
            Log.print("testSuiteWillStart: Bad observer state: \(state), expected: .module or .container")
            return
        }
        
        if module.configError {
            Log.print("testSuiteWillStart: Failed, module config error")
            testSuite.testRun?.stop()
            exit(1)
        }

        guard let tests = testSuite.value(forKey: "_mutableTests") as? NSArray,
              (tests.count == 0 || tests.firstObject is XCTestCase)
        else {
            Log.debug("testSuiteWillStart: container \(testSuite.name)")
            state = .container(suite: ContainerSuite(suite: testSuite, parent: parent), inside: module)
            return
        }

        Log.measure(name: "waiting for ITR") {
            DDTestMonitor.instance?.ensureITRStarted()
        }
        
        Log.debug("testSuiteWillStart: \(testSuite.name)")
        state = .suite(suite: module.suiteStart(name: testSuite.name), inside: parent)
        
        if let itr = DDTestMonitor.instance?.itr {
            let skippableTests = itr.skippableTests.filter { $0.suite == testSuite.name }.map { "-[\(testSuite.name) \($0.name)]" }
            
            let skippedTests = tests.filter { skippableTests.contains(($0 as! XCTest).name) }
            
            let finalTests = tests.filter { !skippableTests.contains(($0 as! XCTest).name) }
            testSuite.setValue(finalTests, forKey: "_mutableTests")
            
            skippedTests.forEach { test in
                self.testCaseWillStart(test as! XCTestCase)
                guard case .test(test: let test, inside: let csuite) = self.state else { return }
                test.end(status: .skip(itr: true))
                self.state = .suite(suite: test.suite, inside: csuite)
            }
            
            if !skippedTests.isEmpty {
                Log.print("ITR skipped \(skippedTests.count) tests")
                module.itrSkipped = true
            }
        }
    }

    func testSuiteDidFinish(_ testSuite: XCTestSuite) {
        switch state {
        case .container(suite: let suite, inside: let module):
            guard suite.suite.name == testSuite.name else {
                Log.print("testSuiteDidFinish: Bad suite: \(testSuite.name), expected: \(suite.suite.name)")
                return
            }
            state = suite.parent == nil ? .module(module) : .container(suite: suite.parent!, inside: module)
            Log.debug("testSuiteDidFinish: container \(testSuite.name)")
        case .suite(suite: let suite, inside: let parent):
            guard suite.name == testSuite.name else {
                Log.print("testSuiteDidFinish: Bad suite: \(testSuite.name), expected: \(suite.name)")
                return
            }
            suite.end()
            state = parent == nil ? .module(suite.module) : .container(suite: parent!, inside: suite.module)
            Log.debug("testSuiteDidFinish: \(testSuite.name)")
        default:
            Log.print("testSuiteDidFinish: Bad observer state: \(state), expected: .suite or .container")
        }
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        guard case .suite(suite: let suite, inside: let parentSuite) = state else {
            Log.print("testCaseWillStart: Bad observer state: \(state), expected: .suite")
            return
        }
        let testName: String
        if let match = DDTestObserver.testNameRegex.firstMatch(in: testCase.name, range: NSRange(location: 0, length: testCase.name.count)),
           let range = Range(match.range(at: 2), in: testCase.name)
        {
            testName = String(testCase.name[range])
        } else {
            testName = testCase.name
        }
        Log.debug("testCaseWillStart: \(testName)")
        state = .test(test: suite.testStart(name: testName), inside: parentSuite)
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        guard case .test(test: let test, inside: let parentSuite) = state else {
            Log.print("testCaseDidFinish: Bad observer state: \(state), expected: .test")
            return
        }
        guard testCase.name.contains(test.name) else {
            Log.print("Bad test: \(testCase), expected: \(test.name)")
            return
        }
        addBenchmarkTagsIfNeeded(testCase: testCase, test: test)
        test.end(status: testCase.testRun?.status ?? .fail)
        state = .suite(suite: test.suite, inside: parentSuite)
        Log.debug("testCaseDidFinish: \(test.name)")
    }

    #if swift(>=5.3)
    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        guard case .test(test: let test, inside: _) = state else {
            Log.print("testCase:didRecord: Bad observer state: \(state), expected: .test")
            return
        }
        test.setErrorInfo(type: issue.compactDescription, message: issue.description, callstack: nil)
    }
    #else
    func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {
        guard case .test(test: let test, inside: _) = state else {
            Log.print("testCase:didFailWithDescription: Bad observer state: \(state), expected: .test")
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

        let maximumAllowedBenchmarks = 16
        var currentlyAddedBenchmarks = 0
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
            if currentlyAddedBenchmarks < maximumAllowedBenchmarks {
                test.addBenchmarkData(name: name, samples: samples, info: info)
                currentlyAddedBenchmarks += 1
            } else {
                Log.print(#"Maximum allowed benchmarks per test reached, following benchmark not added: "\#(name)""#)
            }
        }
    }
}

extension XCTestRun {
    var status: DDTestStatus.ITR {
        if XCTestRun.supportsSkipping && hasBeenSkipped {
            return .skip(itr: false)
        }
        return hasSucceeded ? .pass : .fail
    }
    
    static let supportsSkipping = NSClassFromString("XCTSkippedTestContext") != nil
}
