/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
import MachO
#if SWIFT_PACKAGE
    import DatadogSDKTestingObjc
#endif
@_implementationOnly import EventsExporter

enum DDSymbolicator {
    private static let crashLineRegex = try! NSRegularExpression(pattern: "^([0-9]+)(\\s+)(\\S+ *\\S+)(\\s+)(0x[0-9a-fA-F]+)([ \t]+)(0x[0-9a-fA-F]+)([ \t]+\\+[ \t]+[0-9]+)$?", options: .anchorsMatchLines)
    private static let callStackRegex = try! NSRegularExpression(pattern: "^([0-9]+)(\\s+)(\\S+ *\\S+)(\\s+)(0x[0-9a-fA-F]+)", options: .anchorsMatchLines)

    private static var dSYMFiles: [URL] = {
        var dSYMFiles = [URL]()
        guard let configurationBuildPath = DDEnvironmentValues.getEnvVariable("DYLD_LIBRARY_PATH") else {
            return dSYMFiles
        }
        Log.debug("DYLD_LIBRARY_PATH: \(configurationBuildPath)")
        let fileManager = FileManager.default

        let libraryPaths = configurationBuildPath.components(separatedBy: ":")
        libraryPaths.forEach { path in
            Log.debug("DSYMFILE enumerating: \(path)")
            let buildFolder = URL(fileURLWithPath: path)
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
            let dwarfFolder = dsym.appendingPathComponent("Contents").appendingPathComponent("Resources").appendingPathComponent("DWARF")
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

    /// It symbolicates using atos a given crashLog replacing all addresses by its respective symbol
    static func symbolicate(crashLog: String) -> String {
        let linesLock = NSLock()

        var lines: [String] = crashLog.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        DispatchQueue.concurrentPerform(iterations: lines.count) { lineNumber in
            linesLock.lock()
            let line = lines[lineNumber]
            linesLock.unlock()

            if let match = crashLineRegex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) {
                guard let libraryRange = Range(match.range(at: 3), in: line),
                      let libraryAddressRange = Range(match.range(at: 7), in: line),
                      let callAddressRange = Range(match.range(at: 5), in: line)
                else {
                    return
                }

                let library = String(line[libraryRange])
                let libraryAddress = String(line[libraryAddressRange])
                let callAddress = String(line[callAddressRange])

                if let objectPath = dSYMFiles.first(where: { $0.lastPathComponent == library })?.path ?? BinaryImages.imageAddresses[library]?.path {
                    let symbol = symbolWithAtos(objectPath: objectPath, libraryAdress: libraryAddress, callAddress: callAddress)
                    if !symbol.isEmpty {
                        linesLock.lock()
                        lines[lineNumber] = crashLineRegex.replacementString(for: match, in: line, offset: 0, template: "$1$2$3$4$5$6\(symbol)")
                        linesLock.unlock()
                        return
                    }
                }
                /// No dSYM to symbolicate this line, write symbol Information
                guard let originalCallAdress = Float64(callAddress) else {
                    return
                }
                var callAddressInt = UInt(originalCallAdress)

                /// Calculate the new address of the library, if it is in the map
                if let libraryOffset = BinaryImages.imageAddresses[library]?.slide,
                   let originalLibraryAddress = Float64(libraryAddress)
                {
                    let callOffset = UInt(originalCallAdress) - UInt(originalLibraryAddress)
                    callAddressInt = UInt(libraryOffset) + callOffset
                }

                guard let symbolName = demangleAddress(callAddress: callAddressInt) else {
                    return
                }

                linesLock.lock()
                lines[lineNumber] = crashLineRegex.replacementString(for: match, in: line, offset: 0, template: "$1$2$3$4$5$6\(symbolName)")
                linesLock.unlock()
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Generates a dSYM symbol file from a binary if possible
    /// and adds it to the dSYMFiles for the future
    static func generateDSYMFile(forImageName imageName: String) -> String? {
        guard let binaryPath = BinaryImages.imageAddresses[imageName]?.path else {
            return nil
        }
        let binaryURL = URL(fileURLWithPath: binaryPath)
        let dSYMFileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(binaryURL.lastPathComponent)

        Spawn.command("/usr/bin/dsymutil --minimize --flat \"\(binaryPath)\" --out \"\(dSYMFileURL.path)\"")
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

    /// Manually creates the symbol of a swift test with a given name, this is the name we will locate in the mach image
    /// It only supports test, because only can have one parameter and dont return values, for more complex symbols
    /// a complete Mangler should be implemented
    static func swiftTestMangledName(forClassName className: String, testName: String, throwsError: Bool) -> String {
        let bundleAndClassComponents = className.components(separatedBy: ".")
        guard bundleAndClassComponents.count == 2 else {
            return ""
        }
        let endName = throwsError ? "KF" : "F"

        var componentsAdded = [String]()

        let moduleMangled = mangleIdentifier(identifier: bundleAndClassComponents[0], previousComponents: &componentsAdded, existingModule: "")
        let classMangled = mangleIdentifier(identifier: bundleAndClassComponents[1], previousComponents: &componentsAdded, existingModule: bundleAndClassComponents[0])
        let testNameMangled = mangleIdentifier(identifier: testName, previousComponents: &componentsAdded, existingModule: bundleAndClassComponents[0])
        return "_$s" + moduleMangled + classMangled + "C" + testNameMangled + "yy" + endName
    }

    fileprivate static func mangleIdentifier(identifier: String, previousComponents: inout [String], existingModule: String) -> String {
        if identifier == existingModule {
            return "AA"
        }

        var mangledIdentifier = ""
        let namesToProcess = identifier.separatedByWords.components(separatedBy: " ")
        var accumulator = ""

        let numNamesToProcess = namesToProcess.count
        var replacementHappened = false

        var lastReplacementIndex: Int?
        for namesIdx in 0 ..< numNamesToProcess {
            let wordToProcess = namesToProcess[namesIdx].replacingOccurrences(of: "_", with: "")
            if let index = previousComponents.firstIndex(of: wordToProcess) {
                replacementHappened = true
                let replacingCharacter = Unicode.Scalar(Int(Unicode.Scalar("a").value) + index)
                if !accumulator.isEmpty {
                    mangledIdentifier += "\(accumulator.count)" + accumulator
                }
                accumulator = String(namesToProcess[namesIdx].suffix(namesToProcess[namesIdx].count - wordToProcess.count))
                mangledIdentifier += String(replacingCharacter!)
                lastReplacementIndex = mangledIdentifier.count - 1
                if namesIdx == numNamesToProcess - 1 {
                    mangledIdentifier += "0"
                }
            } else {
                accumulator += namesToProcess[namesIdx]
                if previousComponents.count < 26 {
                    previousComponents.append(wordToProcess)
                }
            }
        }
        if !accumulator.isEmpty {
            mangledIdentifier += "\(accumulator.count)" + accumulator
        }

        if let replacementIndex = lastReplacementIndex {
            mangledIdentifier = DDSymbolicator.upperCase(mangledIdentifier, replacementIndex)
        }
        return replacementHappened ? "0" + mangledIdentifier : mangledIdentifier
    }

    fileprivate static func upperCase(_ myString: String, _ index: Int) -> String {
        var chars = Array(myString) // gets an array of characters
        chars[index] = Character(String(chars[index]).uppercased())
        let modifiedString = String(chars)
        return modifiedString
    }

    /// It locates the address in the image og the library where the symbol is located, it must receive a mangled name
    static func address(forSymbolName name: String, library: String) -> UnsafeMutableRawPointer? {
        guard let imageAddressHeader = BinaryImages.imageAddresses[library]?.header,
              let imageSlide = BinaryImages.imageAddresses[library]?.slide else { return nil }

        let symbol = FindSymbolInImage(name, imageAddressHeader, imageSlide)

        return symbol
    }

    private static func symbolWithAtos(objectPath: String, libraryAdress: String, callAddress: String) -> String {
        var symbol = Spawn.commandWithResult("/usr/bin/atos --fullPath -o \"\(objectPath)\" -l \(libraryAdress) \(callAddress)")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if symbol.hasPrefix("atos cannot load") {
            return ""
        } else if symbol.hasPrefix("Invalid connection: com.apple.coresymbolicationd\n") {
            symbol = String(symbol.dropFirst("Invalid connection: com.apple.coresymbolicationd\n".count))
        }

        if let workspacePath = DDTestMonitor.env.workspacePath {
            symbol = symbol.replacingOccurrences(of: workspacePath + "/", with: "")
        }
        return symbol
    }

    static func atosSymbol(forAddress callAddress: String, library: String) -> String? {
        guard let imageAddress = BinaryImages.imageAddresses[library]
        else { return nil }

        let imagePath = dSYMFiles.first(where: { $0.lastPathComponent == library })?.path ?? imageAddress.path

        let librarySlide = String(format: "%016llx", imageAddress.slide)
        var symbol = Spawn.commandWithResult("/usr/bin/atos --fullPath -o \"\(imagePath)\" -s \(librarySlide) \(callAddress)")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if symbol.isEmpty || symbol.hasPrefix("atos cannot load") || symbol == callAddress {
            return nil
        } else if symbol.hasPrefix("Invalid connection: com.apple.coresymbolicationd\n") {
            symbol = String(symbol.dropFirst("Invalid connection: com.apple.coresymbolicationd\n".count))
        }
        if let workspacePath = DDTestMonitor.env.workspacePath {
            symbol = symbol.replacingOccurrences(of: workspacePath + "/", with: "")
        }
        return symbol
    }

    /// Dumps symbols output for a given libraryName , it must be processed later
    static func symbolsInfo(forLibrary library: String) -> String? {
        guard let imagePath = dSYMFiles.first(where: { $0.lastPathComponent == library })?.path else {
            return nil
        }

        let symbolsOutputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("symbols_output")
        FileManager.default.createFile(atPath: symbolsOutputURL.path, contents: nil, attributes: nil)
        Spawn.commandToFile("/usr/bin/symbols -fullSourcePath -lazy \"\(imagePath)\"", outputPath: symbolsOutputURL.path)
        defer { try? FileManager.default.removeItem(at: symbolsOutputURL) }
        let outputData = try? String(contentsOf: symbolsOutputURL)
        return outputData
    }

    static func getCallStack() -> [String] {
        let callStackSymbols = Thread.callStackSymbols
        let index = callStackSymbols.firstIndex { !$0.contains(exactWord: "DatadogSDKTesting") } ?? 0

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
