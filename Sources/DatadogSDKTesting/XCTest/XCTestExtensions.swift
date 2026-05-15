/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import XCTest

extension XCTestCase {
    var testId: (suite: String, test: String) {
        let cleaned = name.trimmingCharacters(in: Self._trimmedCharacters)
        let index = cleaned.firstIndex(of: " ")
        precondition(index != nil, "unknown test name format \(name)")
        return (String(cleaned[..<index!]), String(cleaned[cleaned.index(after: index!)...]))
    }
    
    private static let _trimmedCharacters: CharacterSet = CharacterSet(charactersIn: "-[]")
}

#if canImport(ObjectiveC)
extension XCTestCase {
    /// Adds a new instance method to this class with selector `newName`. The
    /// added method shares the original method's IMP and type encoding, so
    /// invoking the new selector runs the same code as `original` regardless
    /// of signature (sync, `throws`, `async`, return value).
    ///
    /// XCTest identifies a test by its invocation selector — XCTest's default
    /// `-name` is computed from `[self class]` and `invocation.selector`, and
    /// Xcode keys retry-failure dedup off that identity. Adding an alias and
    /// initialising a retry instance with the alias selector makes Xcode
    /// treat each retry as a separate test run while the original method's
    /// body still runs.
    ///
    /// Idempotent: repeat calls with the same `newName` return the cached
    /// selector. Returns `original` unchanged if it isn't defined on the
    /// class.
    @discardableResult
    class func addAlias(of original: Selector, named newName: String) -> Selector {
        let newSelector = NSSelectorFromString(newName)
        if class_getInstanceMethod(self, newSelector) != nil {
            return newSelector
        }
        guard let originalMethod = class_getInstanceMethod(self, original) else {
            return original
        }
        class_addMethod(self,
                        newSelector,
                        method_getImplementation(originalMethod),
                        method_getTypeEncoding(originalMethod))
        return newSelector
    }
}
#endif

extension XCTestRun {
    var status: TestStatus {
        if hasBeenSkipped { return .skip }
        if let ddRun = self as? DDXCTestSuppressedFailureRun {
            return ddRun.ddHasFailed ? .fail : .pass
        } else {
            return hasSucceeded ? .pass : .fail
        }
    }
}

extension TestRun {
    func addBenchmarkTagsIfNeeded(from testCase: XCTestCase) {
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
                add(benchmark: name, samples: samples, info: info)
                currentlyAddedBenchmarks += 1
            } else {
                Log.print(#"Maximum allowed benchmarks per test reached, following benchmark not added: "\#(name)""#)
            }
        }
    }
    
    fileprivate func measurements(_ metric: AnyObject) -> [Double]? {
        let measurements = metric.value(forKey: "measurements") as? [Double]
        if let measurements = measurements, !measurements.isEmpty {
            return measurements
        }
        return nil
    }
}
