/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

typealias cFunc = @convention(c) () -> Void

class DDCoverageHelper {
    static var instance: DDCoverageHelper?

    var llvmProfileURL: URL
    var storageProfileURL: URL
    var initialCoverageSaved: Bool

    init?() {
        guard !DDEnvironmentValues().disableCodeCoverage,
              let profilePath = DDEnvironmentValues.getEnvVariable("LLVM_PROFILE_FILE"),
              BinaryImages.profileImages.count > 0
        else {
            return nil
        }

        llvmProfileURL = URL(fileURLWithPath: profilePath)
        storageProfileURL = llvmProfileURL.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("profile")
        print(storageProfileURL.path)
        initialCoverageSaved = false
    }

    func clearCounters() {
        BinaryImages.profileImages.forEach {
            Profile_reset_counters($0.beginCountersFuncPtr,
                                   $0.endCountersFuncPtr,
                                   $0.beginDataFuncPtr,
                                   $0.endCountersFuncPtr)
        }
    }

    func setTest(name: String, spanId: String, traceId: String) {
        if !self.initialCoverageSaved {
            profileSetFilename(url: llvmProfileURL)
            internalWriteProfile()
            initialCoverageSaved = true
        }

        let finalName = spanId + "__" + traceId + "__" + name
        if !FileManager.default.fileExists(atPath: storageProfileURL.path) {
            try? FileManager.default.createDirectory(at: storageProfileURL, withIntermediateDirectories: true, attributes: nil)
        }
        let saveURL = storageProfileURL.appendingPathComponent(finalName).appendingPathExtension("profraw")
        profileSetFilename(url: saveURL)
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
