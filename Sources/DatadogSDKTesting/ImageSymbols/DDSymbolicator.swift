/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import MachO
internal import EventsExporter

enum DDSymbolicator {
    private static let callStackRegex = try! NSRegularExpression(pattern: "^([0-9]+)(\\s+)((?:[\\w.] *[\\w.]*)+)(\\s+)(0x[0-9a-fA-F]+)", options: .anchorsMatchLines)
    
    internal static var dsymFilesPath: URL { dsymFilesDir.url }
    internal static let dsymFilesDir: Directory = {
        try! DDTestMonitor.cacheManager!.temp(feature: "dsyms")
    }()

    internal static var dSYMFiles: [URL] = {
        var dSYMFiles = [URL]()
        guard let configurationBuildPath = DDTestMonitor.envReader.get(env: "DYLD_LIBRARY_PATH", String.self) else {
            return dSYMFiles
        }
        Log.debug("DYLD_LIBRARY_PATH: \(configurationBuildPath)")
        let fileManager = FileManager.default

        let libraryPaths = configurationBuildPath.components(separatedBy: ":")
        libraryPaths.forEach { path in
            Log.debug("DSYMFILE enumerating: \(path)")
            let buildFolder = URL(fileURLWithPath: path, isDirectory: true)
            if let dSYMFilesEnumerator = fileManager.enumerator(at: buildFolder,
                                                                includingPropertiesForKeys: nil,
                                                                options: [.skipsHiddenFiles], errorHandler: { url, error -> Bool in
                                                                    Log.debug("DDSymbolicate directoryEnumerator error at \(url): " + error.localizedDescription)
                                                                    return true
                                                                })
            {
                for case let fileURL as URL in dSYMFilesEnumerator {
                    dSYMFiles.append(fileURL)
                }
            }
        }

        if dSYMFiles.isEmpty {
            return dSYMFiles
        }

        /// Flatten folders into individual dSYM files
        var i = 0
        while i < dSYMFiles.count {
            let dsym = dSYMFiles[i]

            if dsym.hasDirectoryPath, dsym.pathExtension.compare("dSYM", options: .caseInsensitive) != .orderedSame {
                let dsyms = try? FileManager.default.contentsOfDirectory(at: dsym, includingPropertiesForKeys: nil, options: []).filter { $0.pathExtension.compare("dSYM", options: .caseInsensitive) == .orderedSame }

                dSYMFiles.remove(at: i)

                if let dsyms = dsyms, !dsyms.isEmpty {
                    dSYMFiles.insert(contentsOf: dsyms, at: i)
                    i += dsyms.count
                }
            } else {
                i += 1
            }
        }

        /// Resolve all dSYM packages to DWARF binaries, remove those that don't have
        /// exactly one binary, and filter out duplicates.
        i = 0
        while i < dSYMFiles.count {
            let dsym = dSYMFiles[i]
            let dwarfFolder = dsym
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("DWARF", isDirectory: true)
            guard let binaries = try? FileManager.default.contentsOfDirectory(at: dwarfFolder, includingPropertiesForKeys: nil, options: []), binaries.count == 1 else {
                dSYMFiles.remove(at: i)
                continue
            }

            if i > 0, dSYMFiles[0 ..< i].contains(binaries[0]) {
                dSYMFiles.remove(at: i)
                continue /// duplicate
            }
            dSYMFiles[i] = binaries[0]
            i += 1
        }
        Log.debug("DSYMFILES found: \(dSYMFiles)")
        return dSYMFiles
    }()

    /// Symbolicates the frames of a `CrashLog` in place. Frames are grouped by
    /// `(binary, library load address)` so each unique binary is opened by atos exactly once —
    /// turning N per-frame spawns into M per-binary spawns (M ≪ N). Frames whose binary cannot
    /// be located fall back to `dladdr` + Swift demangling against the current process.
    static func symbolicate(_ crashLog: inout CrashLog) {
        struct Pending {
            let threadIdx: Int
            let frameIdx: Int
            let library: String
            let instructionAddress: UInt64
            let objectAddress: UInt64
            let objectPath: String?
        }

        // Flatten frames and resolve a binary path per frame in a single sweep.
        var pending: [Pending] = []
        for (tIdx, thread) in crashLog.threads.enumerated() {
            for (fIdx, frame) in thread.frames.enumerated() {
                let objectURL = dSYMFiles.first(where: { $0.lastPathComponent == frame.library })
                    ?? BinaryImages.imageAddresses[frame.library]?.path
                pending.append(Pending(
                    threadIdx: tIdx, frameIdx: fIdx,
                    library: frame.library,
                    instructionAddress: frame.instructionAddress,
                    objectAddress: frame.objectAddress,
                    objectPath: objectURL?.path
                ))
            }
        }

        // Group by (objectPath, libraryLoadAddress) so each group becomes one atos invocation.
        struct BatchKey: Hashable { let objectPath: String; let libraryAddress: UInt64 }
        var groups: [BatchKey: [Int]] = [:]
        for (i, p) in pending.enumerated() {
            guard let path = p.objectPath else { continue }
            groups[BatchKey(objectPath: path, libraryAddress: p.objectAddress), default: []].append(i)
        }

        let workspacePath = DDTestMonitor.env.workspacePath
        let resolvedSymbols: Synced<[Int: String]> = .init([:])
        let groupList = Array(groups)
        DispatchQueue.concurrentPerform(iterations: groupList.count) { gIdx in
            let (key, frameIndices) = groupList[gIdx]
            let addresses = frameIndices
                .map { String(format: "0x%llx", pending[$0].instructionAddress) }
                .joined(separator: " ")
            let libraryHex = String(format: "0x%llx", key.libraryAddress)
            guard let response = Spawn.command(
                try: "/usr/bin/atos --fullPath -o \"\(key.objectPath)\" -l \(libraryHex) \(addresses)",
                log: Log.instance
            ) else { return }
            if response.error.hasPrefix("atos cannot load") { return }
            let symbols = response.output.components(separatedBy: "\n")
            guard symbols.count == frameIndices.count else { return }

            resolvedSymbols.update { resolvedSymbols in
                for (i, frameIdx) in frameIndices.enumerated() {
                    var symbol = symbols[i]
                    if symbol.isEmpty { continue }
                    if let workspacePath {
                        symbol = symbol.replacingOccurrences(of: workspacePath + "/", with: "")
                    }
                    resolvedSymbols[frameIdx] = symbol
                }
            }
        }

        // Apply resolved symbols back into the crash log; fall back to dladdr+demangle for the rest.
        let resolved = resolvedSymbols.value
        for (i, p) in pending.enumerated() {
            if let symbol = resolved[i] {
                crashLog.threads[p.threadIdx].frames[p.frameIdx].symbolicated = symbol
            } else if let symbol = dladdrFallback(library: p.library,
                                                  instructionAddress: p.instructionAddress,
                                                  objectAddress: p.objectAddress)
            {
                crashLog.threads[p.threadIdx].frames[p.frameIdx].symbolicated = symbol
            }
        }
    }

    /// Translates a crash-time PC into the equivalent address in the current process and looks up
    /// the symbol via `dladdr`. Returns `nil` if the binary isn't loaded in this process.
    private static func dladdrFallback(library: String, instructionAddress: UInt64, objectAddress: UInt64) -> String? {
        var lookupAddr = UInt(instructionAddress)
        if let currentSlide = BinaryImages.imageAddresses[library]?.slide, objectAddress > 0 {
            let offset = instructionAddress &- objectAddress
            lookupAddr = UInt(currentSlide) &+ UInt(offset)
        }
        return demangleAddress(callAddress: lookupAddr)
    }

    /// Generates a dSYM symbol file from a binary if possible
    /// and adds it to the dSYMFiles for the future
    static func generateDSYMFile(forImageName imageName: String) -> String? {
        guard let binaryURL = BinaryImages.imageAddresses[imageName]?.path else {
            return nil
        }
        let dSYMFileURL = dsymFilesPath
            .appendingPathComponent(binaryURL.lastPathComponent, isDirectory: false)
        
        do {
            try Spawn.command("/usr/bin/dsymutil --flat \"\(binaryURL.path)\" --out \"\(dSYMFileURL.path)\"")
        } catch {
            Log.debug("DSYM \(binaryURL.path) generation failed \(error)")
            return nil
        }
        
        if FileManager.default.fileExists(atPath: dSYMFileURL.path) {
            dSYMFiles.append(dSYMFileURL)
            return dSYMFileURL.path
        }
        return nil
    }

    static func createDSYMFileIfNeeded(forImageName imageName: String) {
        let dSYMFile = DDSymbolicator.dSYMFiles.first(where: { $0.lastPathComponent == imageName })
        if dSYMFile == nil {
            _ = DDSymbolicator.generateDSYMFile(forImageName: imageName)
        }
    }

    static func atosSymbol(forAddress callAddress: String, library: String) -> String? {
        guard let imageAddress = BinaryImages.imageAddresses[library] else { return nil }

        let imagePath = dSYMFiles.first(where: { $0.lastPathComponent == library })?.path ?? imageAddress.path.path

        let librarySlide = String(format: "%016llx", imageAddress.slide)
        
        guard let response = Spawn.command(
            try: "/usr/bin/atos --fullPath -o \"\(imagePath)\" -s \(librarySlide) \(callAddress)", log: Log.instance
        ) else {
            return nil
        }
        var symbol = response.output
        if response.error.hasPrefix("atos cannot load") || symbol.isEmpty || symbol == callAddress {
            return nil
        }
        if let workspacePath = DDTestMonitor.env.workspacePath {
            symbol = symbol.replacingOccurrences(of: workspacePath + "/", with: "")
        }
        return symbol
    }

    /// Dumps symbols output for a given libraryName , it must be processed later
    static func symbolsInfo(forLibrary library: String) -> URL? {
        guard let imagePath = dSYMFiles.first(where: { $0.lastPathComponent == library })?.path else {
            return nil
        }
        let symbolsOutputURL = dsymFilesPath.appendingPathComponent("\(library).symbols", isDirectory: false)
        do {
            try Spawn.command("/usr/bin/symbols -fullSourcePath -lazy \"\(imagePath)\"", output: symbolsOutputURL)
        } catch {
            Log.debug("symbolsInfo for \(library) failed: \(error)")
            try? FileManager.default.removeItem(at: symbolsOutputURL)
            return nil
        }
        return symbolsOutputURL
    }

    static func getCallStack(hidesLibrarySymbols: Bool = true) -> [String] {
        let callStackSymbols = Thread.callStackSymbols
        let index: Array<String>.Index
        if hidesLibrarySymbols {
            index = callStackSymbols.firstIndex { !$0.contains(exactWord: "DatadogSDKTesting") } ?? callStackSymbols.startIndex
        } else {
            index = callStackSymbols.index(0, offsetBy: 2)
        }

        let demangled: [String] = callStackSymbols.dropFirst(index)
            .map {
                guard let match = callStackRegex.firstMatch(in: $0, options: [], range: NSRange(location: 0, length: $0.count)),
                      let callAddressRange = Range(match.range(at: 5), in: $0),
                      let callAddress = Float64(String($0[callAddressRange])) else { return "<Unknown>" }

                let symbol = DDSymbolicator.demangleAddress(callAddress: UInt(callAddress)) ?? "<Unknown>"
                return callStackRegex.replacementString(for: match, in: String($0), offset: 0, template: "$3\t\(symbol)")
            }

        let enumeratedCallstack = zip(demangled.indices, demangled).map { "\($0)\t\($1)" }

        return enumeratedCallstack
    }

    static func getCallStackSymbolicated() -> [String] {
        let callStackSymbols = Thread.callStackSymbols
        let index = callStackSymbols.firstIndex { !$0.contains(exactWord: "DatadogSDKTesting") } ?? 0

        let symbolicated: [String] = callStackSymbols.dropFirst(index)
            .compactMap {
                guard let match = callStackRegex.firstMatch(in: $0, options: [], range: NSRange(location: 0, length: $0.count)),
                      let libraryRange = Range(match.range(at: 3), in: $0),
                      let callAddressRange = Range(match.range(at: 5), in: $0)
                else {
                    return nil
                }
                let library = String($0[libraryRange])
                let callAddress = String($0[callAddressRange])

                if let symbol = atosSymbol(forAddress: callAddress, library: library) {
                    return symbol
                }

                guard let originalCallAdress = Float64(callAddress) else {
                    return nil
                }
                return DDSymbolicator.demangleAddress(callAddress: UInt(originalCallAdress)) ?? "<Unknown>"
            }
        let enumeratedCallstack = zip(symbolicated.indices, symbolicated).map { "\($0) \($1)" }
        return enumeratedCallstack
    }

    static func demangleAddress(callAddress: UInt) -> String? {
        guard let ptr = UnsafeRawPointer(bitPattern: callAddress) else {
            return nil
        }

        var info = Dl_info()
        let result = dladdr(ptr, &info)
        if result != 0, info.dli_sname != nil {
            return demangleName(String(cString: info.dli_sname))
        } else {
            return nil
        }
    }

    private static func demangleName(_ mangledName: String) -> String {
        return mangledName.utf8CString.withUnsafeBufferPointer {
            mangledNameUTF8CStr in

            let demangledNamePtr = _stdlib_demangleImpl(
                mangledName: mangledNameUTF8CStr.baseAddress,
                mangledNameLength: UInt(mangledNameUTF8CStr.count - 1),
                outputBuffer: nil,
                outputBufferSize: nil,
                flags: 0
            )

            if let demangledNamePtr = demangledNamePtr {
                let demangledName = String(cString: demangledNamePtr)
                free(demangledNamePtr)
                return demangledName
            }
            return mangledName
        }
    }

    static func calculateCrashedThread(stack: String) -> String {
        var charIndex = 0
        for line in stack.components(separatedBy: "\n").lazy {
            if line.hasPrefix("Thread"), line.contains("Crashed:") {
                break
            }
            charIndex += line.count + 1
        }

        let start = stack.index(stack.startIndex, offsetBy: charIndex)
        let end = stack.index(start, offsetBy: 5000)
        return String(stack[start ... end])
    }
}

@_silgen_name("swift_demangle")
func _stdlib_demangleImpl(
    mangledName: UnsafePointer<CChar>?,
    mangledNameLength: UInt,
    outputBuffer: UnsafeMutablePointer<CChar>?,
    outputBufferSize: UnsafeMutablePointer<UInt>?,
    flags: UInt32
) -> UnsafeMutablePointer<CChar>?
