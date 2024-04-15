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
    var storageProfileURL: URL
    var initialCoverageSaved: Bool
    let coverageWorkQueue: OperationQueue

    init?() {
        guard let profilePath = DDTestMonitor.envReader.get(env: "LLVM_PROFILE_FILE", String.self),
              BinaryImages.profileImages.count > 0
        else {
            Log.print("Coverage not properly enabled in project, check documentation")
            Log.debug("LLVM_PROFILE_FILE: \(DDTestMonitor.envReader.get(env: "LLVM_PROFILE_FILE") ?? "NIL")")
            Log.debug("Profile Images count: \(BinaryImages.profileImages.count)")
            return nil
        }

        llvmProfileURL = URL(fileURLWithPath: profilePath)
        storageProfileURL = llvmProfileURL.deletingLastPathComponent().appendingPathComponent("DDTestingCoverage")
        Log.debug("LLVM Coverage location: \(llvmProfileURL.path)")
        Log.debug("DDCoverageHelper location: \(storageProfileURL.path)")
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

        if !FileManager.default.fileExists(atPath: storageProfileURL.path) {
            try? FileManager.default.createDirectory(at: storageProfileURL, withIntermediateDirectories: true, attributes: nil)
        }
        let saveURL = getURLForTest(name: name, testSessionId: testSessionId, testSuiteId: testSuiteId, spanId: spanId)
        profileSetFilename(url: saveURL)
    }

    func getURLForTest(name: String, testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64) -> URL {
        let finalName = String(testSessionId) + "__" + String(testSuiteId) + "__" + String(spanId) + "__" + name
        return storageProfileURL.appendingPathComponent(finalName).appendingPathExtension("profraw")
    }

    func writeProfile() {
        // Write first to our test file
        internalWriteProfile()

        // Write to llvm original destination
        profileSetFilename(url: llvmProfileURL)
        internalWriteProfile()
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

    fileprivate static func generateProfData(profrawFile: URL) -> URL {
        let outputURL = profrawFile.deletingPathExtension().appendingPathExtension("profdata")
        let input = profrawFile.path
        let outputPath = outputURL.path
        let commandToRun = #"xcrun llvm-profdata merge -sparse "\#(input)" -o "\#(outputPath)""#
        let llvmProfDataOutput = Spawn.commandWithResult(commandToRun)
        Log.debug("llvm-profdata output: \(llvmProfDataOutput)")
        return outputURL
    }

    static func getModuleCoverage(profrawFile: URL, binaryImagePaths: [String]) -> LLVMTotalsCoverageFormat? {
        let profDataURL = DDCoverageHelper.generateProfData(profrawFile: profrawFile)
        Thread.sleep(forTimeInterval: 0.1)
        let covJsonURL = profDataURL.deletingLastPathComponent().appendingPathComponent("coverageFile").appendingPathExtension("json")
        let binariesPath = binaryImagePaths.map { #""\#($0)""# }.joined(separator: " -object ")
        let commandToRun = #"xcrun llvm-cov export -instr-profile "\#(profDataURL.path)" \#(binariesPath) > "\#(covJsonURL.path)""#
        let llvmCovOutput = Spawn.commandWithResult(commandToRun)
        Log.debug("llvm-cov output: \(llvmCovOutput)")
        return LLVMTotalsCoverageFormat(fromURL: covJsonURL)
    }
}
