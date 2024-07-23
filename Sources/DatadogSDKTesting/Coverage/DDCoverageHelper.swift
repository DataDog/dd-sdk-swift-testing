/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@_implementationOnly import EventsExporter
import Foundation
import CDatadogSDKTesting

typealias cFunc = @convention(c) () -> Void

class DDCoverageHelper {
    var llvmProfileURL: URL
    var storagePath: Directory
    var initialCoverageSaved: Bool
    let coverageWorkQueue: OperationQueue

    init?(storagePath: Directory) {
        guard let profilePath = Self.profileGetFileName(), BinaryImages.profileImages.count > 0 else {
            Log.print("Coverage not properly enabled in project, check documentation")
            Log.debug("LLVM_PROFILE_FILE: \(Self.profileGetFileName() ?? "NIL")")
            Log.debug("Profile Images count: \(BinaryImages.profileImages.count)")
            return nil
        }
        
        guard let path = try? storagePath.createSubdirectory(path: "coverage") else {
            Log.debug("Can't create subdirectory in: \(storagePath)")
            return nil
        }

        llvmProfileURL = URL(fileURLWithPath: profilePath)
        self.storagePath = path
        Log.debug("LLVM Coverage location: \(llvmProfileURL.path)")
        Log.debug("DDCoverageHelper location: \(path.url.path)")
        initialCoverageSaved = false
        coverageWorkQueue = OperationQueue()
        coverageWorkQueue.qualityOfService = .background
        coverageWorkQueue.maxConcurrentOperationCount = (ProcessInfo.processInfo.activeProcessorCount - 1)
    }

    func clearCounters() {
        BinaryImages.profileImages.forEach {
            ProfileResetCounters($0.beginCountersFuncPtr,
                                 $0.endCountersFuncPtr,
                                 $0.beginDataFuncPtr,
                                 $0.endCountersFuncPtr)
        }
    }

    func setTest(name: String, testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64) {
        if !self.initialCoverageSaved {
            profileSetFilename(url: llvmProfileURL)
            internalWriteProfile()
            initialCoverageSaved = true
        }
        let saveURL = getURLForTest(name: name, testSessionId: testSessionId, testSuiteId: testSuiteId, spanId: spanId)
        profileSetFilename(url: saveURL)
    }

    func getURLForTest(name: String, testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64) -> URL {
        let finalName = String(testSessionId) + "__" + String(testSuiteId) + "__" + String(spanId) + "__" + name
        return storagePath.url.appendingPathComponent(finalName).appendingPathExtension("profraw")
    }

    func writeProfile() {
        // Write first to our test file
        internalWriteProfile()

        // Write to llvm original destination
        profileSetFilename(url: llvmProfileURL)
        internalWriteProfile()
    }
    
    func removeStoragePath() {
        try? storagePath.delete()
    }

    private func internalWriteProfile() {
        BinaryImages.profileImages.forEach {
            let llvm_profile_write_file = unsafeBitCast($0.writeFileFuncPtr, to: cFunc.self)
            llvm_profile_write_file()
        }
    }

    private func profileSetFilename(url: URL) {
        setenv("LLVM_PROFILE_FILE", url.path, 1)
        BinaryImages.profileImages.forEach {
            if $0.profileInitializeFileFuncPtr != nil {
                let llvm_profile_initialize_file = unsafeBitCast($0.profileInitializeFileFuncPtr, to: cFunc.self)
                llvm_profile_initialize_file()
            }
        }
    }
    
    private static func profileGetFileName() -> String? {
        getenv("LLVM_PROFILE_FILE").map { String(cString: $0) }
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
        Thread.sleep(forTimeInterval: 0.1)
        let covJsonURL = profDataURL.deletingLastPathComponent().appendingPathComponent("coverageFile").appendingPathExtension("json")
        let binariesPath = binaryImagePaths.map { #""\#($0)""# }.joined(separator: " -object ")
        let commandToRun = #"xcrun llvm-cov export -instr-profile "\#(profDataURL.path)" \#(binariesPath) > "\#(covJsonURL.path)""#
        guard let llvmCovOutput = Spawn.combined(try: commandToRun, log: Log.instance) else {
            return nil
        }
        Log.debug("llvm-cov output: \(llvmCovOutput)")
        defer { try? FileManager.default.removeItem(at: covJsonURL) }
        return LLVMTotalsCoverageFormat(fromURL: covJsonURL)
    }
}
