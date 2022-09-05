/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
#if SWIFT_PACKAGE
import DatadogSDKTestingObjc
#endif

typealias cFunc = @convention(c) () -> Void

class DDCoverageHelper {
    var llvmProfileURL: URL
    var storageProfileURL: URL
    var initialCoverageSaved: Bool
    let coverageWorkQueue: OperationQueue

    init?() {
        guard DDTestMonitor.env.coverageEnabled,
              let profilePath = DDEnvironmentValues.getEnvVariable("LLVM_PROFILE_FILE"),
              BinaryImages.profileImages.count > 0
        else {
            Log.debug("DDCoverageHelper could not be instanced")
            return nil
        }

        llvmProfileURL = URL(fileURLWithPath: profilePath)
        storageProfileURL = llvmProfileURL.deletingLastPathComponent().appendingPathComponent("DDTestingCoverage")
        Log.debug("DDCoverageHelper location: \(storageProfileURL.path)")
        initialCoverageSaved = false
        coverageWorkQueue = OperationQueue()
        coverageWorkQueue.qualityOfService = .background
        coverageWorkQueue.maxConcurrentOperationCount = (ProcessInfo.processInfo.activeProcessorCount -  1)
    }

    func clearCounters() {
        BinaryImages.profileImages.forEach {
            Profile_reset_counters($0.beginCountersFuncPtr,
                                   $0.endCountersFuncPtr,
                                   $0.beginDataFuncPtr,
                                   $0.endCountersFuncPtr)
        }
    }

    func setTest(name: String, traceId: UInt64, spanId: UInt64) {
        if !self.initialCoverageSaved {
            profileSetFilename(url: llvmProfileURL)
            internalWriteProfile()
            initialCoverageSaved = true
        }

        if !FileManager.default.fileExists(atPath: storageProfileURL.path) {
            try? FileManager.default.createDirectory(at: storageProfileURL, withIntermediateDirectories: true, attributes: nil)
        }
        let saveURL = getURLForTest(name: name, traceId: traceId, spanId: spanId)
        profileSetFilename(url: saveURL)
    }

    func getURLForTest(name: String, traceId: UInt64, spanId: UInt64) -> URL {
        let finalName = String(traceId) + "__" + String(spanId) + "__" + name
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
}
