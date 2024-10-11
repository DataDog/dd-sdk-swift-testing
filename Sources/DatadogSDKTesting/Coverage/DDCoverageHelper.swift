/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import EventsExporter
@_implementationOnly import CDatadogSDKTesting

typealias cFunc = @convention(c) () -> Void

class DDCoverageHelper {
    var llvmProfileURL: URL
    var storagePath: Directory
    var initialCoverageSaved: Bool
    let isTotal: Bool
    let coverageWorkQueue: OperationQueue

    init?(storagePath: Directory, total: Bool, priority: CodeCoveragePriority) {
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
        isTotal = total
        self.storagePath = path
        Log.debug("LLVM Coverage location: \(llvmProfileURL.path)")
        Log.debug("DDCoverageHelper location: \(path.url.path)")
        initialCoverageSaved = false
        coverageWorkQueue = OperationQueue()
        coverageWorkQueue.qualityOfService = priority.qos
        coverageWorkQueue.maxConcurrentOperationCount = max(ProcessInfo.processInfo.activeProcessorCount - 1, 1)
        setFileLimit()
    }

    func clearCounters() {
        BinaryImages.profileImages.forEach {
            ProfileResetCounters($0.beginCountersFuncPtr,
                                 $0.endCountersFuncPtr,
                                 $0.beginDataFuncPtr,
                                 $0.endCountersFuncPtr)
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

    func setTest(name: String, testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64) {
        if !self.initialCoverageSaved {
            profileSetFilename(url: llvmProfileURL)
            Self.internalWriteProfile()
            initialCoverageSaved = true
        }
        let saveURL = getURLForTest(name: name, testSessionId: testSessionId, testSuiteId: testSuiteId, spanId: spanId)
        profileSetFilename(url: saveURL)
    }

    func getURLForTest(name: String, testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64) -> URL {
        var cleanedName = name.components(separatedBy: Self.nameNotAllowed)
            .filter { $0.count > 0 }
            .joined(separator: "+")
        if cleanedName.count > 20 {
            cleanedName = "\(cleanedName.prefix(10))-\(cleanedName.suffix(10))"
        }
        let finalName = "\(testSessionId)__\(testSuiteId)__\(spanId)__\(cleanedName)"
        return storagePath.url.appendingPathComponent(finalName).appendingPathExtension("profraw")
    }

    func writeTestProfile() {
        // Write first to our test file
        Self.internalWriteProfile()
        if isTotal {
            // Switch profile to llvm original destination
            profileSetFilename(url: llvmProfileURL)
            // Write to llvm original destination
            Self.internalWriteProfile()
        }
    }
    
    func removeStoragePath() {
        try? storagePath.delete()
    }

    private static func internalWriteProfile() {
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
    
    static func getLineCodeCoverage() -> Double? {
        // Check do we have profiling enabled
        guard let llvmProfilePath = profileGetFileName() else { return nil }
        // Save all profiling data
        internalWriteProfile()
        // Locate profraw file
        let profileFolder = URL(fileURLWithPath: llvmProfilePath).deletingLastPathComponent()
        guard let file = FileManager.default
            .enumerator(at: profileFolder, includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants)
            .flatMap({ $0.first { ($0 as? URL)?.pathExtension == "profraw" } })
            .map({ $0 as! URL })
        else { return nil }
        // get coverage
        let images = BinaryImages.binaryImagesPath
        let coverage = DDCoverageHelper.getModuleCoverage(profrawFile: file, binaryImagePaths: images)
        return coverage?.data.first?.totals.lines.percent
    }
    
    static func load() -> Bool {
        guard let llvmProfilePath = profileGetFileName() else { return false }
        Log.debug("DDCoverageHelper patching environment: \(llvmProfilePath)")
        let newEnv = llvmProfilePath.replacingOccurrences(of: "%c", with: "")
        setenv("LLVM_PROFILE_FILE", newEnv, 1)
        Log.debug("DDCoverageHelper patched environment")
        return true
    }
    
    private static let nameNotAllowed: CharacterSet = .alphanumerics.union(.init(charactersIn: "-._")).inverted
}
