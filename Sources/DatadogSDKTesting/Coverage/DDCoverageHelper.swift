/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import EventsExporter
@_implementationOnly import CDatadogSDKTesting
@_implementationOnly import CodeCoverage

typealias cFunc = @convention(c) () -> Void

protocol TestCoverageCollector: Feature {
    func startTest()
    func endTest(testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64)
}

final class DDCoverageHelper: TestCoverageCollector {
    static var id: String = "Coverage Helper"
    
    let collector: CoverageCollector
    let exporter: EventsExporterProtocol
    let workspacePath: String?

    let storagePath: Directory
    let debug: Bool
    let coverageWorkQueue: OperationQueue

    init?(storagePath: Directory, exporter: EventsExporterProtocol, workspacePath: String?, priority: CodeCoveragePriority, debug: Bool) {
        do {
            self.collector = try CoverageCollector(for: PlatformUtils.xcodeVersion, temp: storagePath.url)
            self.debug = debug
            self.storagePath = storagePath
            self.exporter = exporter
            self.workspacePath = workspacePath
            coverageWorkQueue = OperationQueue()
            coverageWorkQueue.qualityOfService = priority.qos
            coverageWorkQueue.maxConcurrentOperationCount = max(ProcessInfo.processInfo.activeProcessorCount - 1, 1)
            setFileLimit()
        } catch {
            Log.print("Coverage initialisation error: \(error)")
            return nil
        }
    }
    
    func startTest() {
        do {
            try collector.startCoverageGathering()
        } catch {
            Log.debug("Can't start coverage gathering, error: \(error)")
        }
    }
    
    func endTest(testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64) {
        let file: URL
        do {
            file = try collector.stopCoverageGathering()
        } catch {
            Log.debug("Coverage gathering error: \(error)")
            return
        }
        coverageWorkQueue.addOperation {
            guard FileManager.default.fileExists(atPath: file.path) else {
                return
            }
            self.exporter.export(coverage: file, processor: self.collector.processor, workspacePath: self.workspacePath,
                                 testSessionId: testSessionId, testSuiteId: testSuiteId, spanId: spanId)
        }
    }
    
    private func setFileLimit() {
        var limit = rlimit()
        let filesMax = 4096
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else {
            Log.debug("Can't get open file limit")
            return
        }
        let curLimit = limit.rlim_cur
        guard curLimit < filesMax else {
            Log.debug("Open file limit is good: \(curLimit)")
            return
        }
        limit.rlim_cur = rlim_t(filesMax)
        if setrlimit(RLIMIT_NOFILE, &limit) == 0 {
            Log.debug("Updated open file limit to \(filesMax) from \(curLimit)")
        } else {
            Log.debug("Can't increase open file limit")
        }
    }
    
    deinit {
        if !debug {
            try? storagePath.delete()
        } else {
            Log.debug("DDCoverageHelper storage path: \(storagePath.url.path)")
        }
    }
    
    func removeStoragePath() {
        try? storagePath.delete()
    }
    
    func stop() {
        let oldQos = coverageWorkQueue.qualityOfService
        let oldConcurrency = coverageWorkQueue.maxConcurrentOperationCount
        /// We need to wait for all the traces to be written to the backend before exiting
        coverageWorkQueue.maxConcurrentOperationCount = ProcessInfo.processInfo.activeProcessorCount
        coverageWorkQueue.qualityOfService = .userInteractive
        coverageWorkQueue.waitUntilAllOperationsAreFinished()
        coverageWorkQueue.qualityOfService = oldQos
        coverageWorkQueue.maxConcurrentOperationCount = oldConcurrency
    }

    fileprivate static func generateProfData(profrawFile: URL) -> URL? {
        let outputURL = profrawFile.deletingPathExtension().appendingPathExtension("profdata")
        let input = profrawFile.path
        let outputPath = outputURL.path
        let commandToRun = #"xcrun llvm-profdata merge -sparse "\#(input)" -o "\#(outputPath)""#
        guard let llvmProfDataOutput = Spawn.combined(try: commandToRun, log: Log.instance) else {
            return nil
        }
        Log.debug("llvm-profdata output: \(llvmProfDataOutput)")
        return outputURL
    }

    static func getModuleCoverage(profrawFile: URL, binaryImagePaths: [String]) -> LLVMTotalsCoverageFormat? {
        guard let profDataURL = DDCoverageHelper.generateProfData(profrawFile: profrawFile) else {
            return nil
        }
        let covJsonURL = profDataURL
            .deletingLastPathComponent()
            .appendingPathComponent("TotalCoverage.json", isDirectory: false)
        let binariesPath = binaryImagePaths.map { #""\#($0)""# }.joined(separator: " -object ")
        let commandToRun = #"xcrun llvm-cov export -instr-profile "\#(profDataURL.path)" \#(binariesPath) > "\#(covJsonURL.path)""#
        guard let llvmCovOutput = Spawn.combined(try: commandToRun, log: Log.instance) else {
            return nil
        }
        Log.debug("llvm-cov output: \(llvmCovOutput)")
        defer { try? FileManager.default.removeItem(at: covJsonURL) }
        return LLVMTotalsCoverageFormat(fromURL: covJsonURL)
    }
    
    static func getLineCodeCoverage() -> Double? {
        // Check do we have profiling enabled
        guard let llvmProfilePath = try? CoverageCollector.currentCoverageFile else { return nil }
        let binaries = CoveredBinary.currentProcessBinaries
        // if not continuous mode then save all data
        if !llvmProfilePath.contains(exactWord: "%c") {
            // Save all profiling data
            binaries.forEach { $0.write() }
        }
        // Locate profraw file
        guard let llvmProfileUrl = CoverageCollector.currentCoverageFileURL else { return nil }
        // Get total coverage
        let coverage = DDCoverageHelper.getModuleCoverage(profrawFile: llvmProfileUrl,
                                                          binaryImagePaths: binaries.map { $0.path })
        return coverage?.data.first?.totals.lines.percent
    }
}
