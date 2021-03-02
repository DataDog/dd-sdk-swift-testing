/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import MachO

struct DDSymbolicator {
    private static let crashLineRegex = try! NSRegularExpression(pattern: "^([0-9]+)([ \t]+)([^ \t]+)([ \t]+)(0x[0-9a-fA-F]+)([ \t]+)(0x[0-9a-fA-F]+)([ \t]+\\+[ \t]+[0-9]+)$?", options: .anchorsMatchLines)
    private static let binaryImageLines = try! NSRegularExpression(pattern: "^\\s*(0x[0-9a-fA-F]+)\\s*\\-\\s*(0x[0-9a-fA-F]+)\\s*\\+?(.+)\\s+(.+)\\s+\\<(.+)\\>\\s+(\\/.*)\\s*$", options: [.anchorsMatchLines, .caseInsensitive])

    private static var dSYMFiles: [URL] = {
        var dSYMFiles = [URL]()
        guard let configurationBuildPath = DDEnvironmentValues.getEnvVariable("DYLD_LIBRARY_PATH") else {
            return dSYMFiles
        }

        let fileManager = FileManager.default
        let buildFolder = URL(fileURLWithPath: configurationBuildPath)
        let dSYMFilesEnumerator = fileManager.enumerator(at: buildFolder,
                                                         includingPropertiesForKeys: nil,
                                                         options: [.skipsHiddenFiles], errorHandler: { (url, error) -> Bool in
                                                             print("[DDSymbolicate] directoryEnumerator error at \(url): ", error)
                                                             return true
                                                         })!
        for case let fileURL as URL in dSYMFilesEnumerator {
            if fileURL.pathExtension.compare("dSYM", options: .caseInsensitive) != .orderedSame {
                dSYMFiles.append(fileURL)
            }
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
        return dSYMFiles
    }()

    public static func symbolicate(crashLog: String) -> String {
        var lines: [String] = crashLog.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        /// User library addresses are randomized each time an app is run, create a map to locate library addresses by name,
        /// system libraries are not so address returned is 0
        let numImages = _dyld_image_count()
        var imageAddresses = [String: UInt]()
        for i in 0 ..< numImages {
            let name = URL(fileURLWithPath: String(cString: _dyld_get_image_name(i))).lastPathComponent
            let address = UInt(_dyld_get_image_vmaddr_slide(i))
            if address != 0 {
                imageAddresses[name] = address
            }
        }

        var binaries = [String: String]()
        for i in 0 ..< lines.count {
            let line = lines[i]
            if let match = binaryImageLines.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) {
                guard let startAddressRange = Range(match.range(at: 1), in: line),
                      let pathRange = Range(match.range(at: 6), in: line)
                else {
                    continue
                }
                binaries[String(line[startAddressRange])] = String(line[pathRange])
            }
        }

        for i in 0 ..< lines.count {
            let line = lines[i]
            if let match = crashLineRegex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) {
                guard let libraryRange = Range(match.range(at: 3), in: line),
                      let libraryAddressRange = Range(match.range(at: 7), in: line),
                      let callAddressRange = Range(match.range(at: 5), in: line)
                else {
                    continue
                }

                let library = String(line[libraryRange])
                let libraryAddress = String(line[libraryAddressRange])
                let callAddress = String(line[callAddressRange])

                #if os(iOS) || os(macOS)
                    if let dsym = dSYMFiles.first(where: { $0.lastPathComponent == library }) {
                        let symbol = symbolWithAtos(objectPath: dsym.path, libraryAdress: libraryAddress, callAddress: callAddress)
                        if !symbol.isEmpty {
                            lines[i] = crashLineRegex.replacementString(for: match, in: line, offset: 0, template: "$1$2$3$4$5$6\(symbol)")
                            continue
                        }
                    } else {
                        if let symbolFilePath = binaries[libraryAddress] {
                            let symbol = symbolWithAtos(objectPath: symbolFilePath, libraryAdress: libraryAddress, callAddress: callAddress)
                            if !symbol.isEmpty {
                                lines[i] = crashLineRegex.replacementString(for: match, in: line, offset: 0, template: "$1$2$3$4$5$6\(symbol)")
                                continue
                            }
                        }
                    }
                #endif
                /// No dSYM to symbolicate this line, write symbol Information
                guard let originalCallAdress = Float64(callAddress) else {
                    continue
                }
                var callAdress = UInt(originalCallAdress)

                /// Calculate the new address of the library, if it is in the map
                if let libraryOffset = imageAddresses[library],
                   let originalLibraryAddress = Float64(libraryAddress)
                {
                    let callOffset = UInt(originalCallAdress) - UInt(originalLibraryAddress)
                    callAdress = libraryOffset + callOffset
                }

                guard let ptr = UnsafeRawPointer(bitPattern: UInt(callAdress)) else {
                    continue
                }

                var info = Dl_info()
                let result = dladdr(ptr, &info)
                if result != 0 {
                    let symbolName = info.dli_sname != nil ? demangleName(String(cString: info.dli_sname)) : ""
                    lines[i] = crashLineRegex.replacementString(for: match, in: line, offset: 0, template: "$1$2$3$4$5$6\(symbolName)")
                }
                continue
            }
        }
        return lines.joined(separator: "\n")
    }

#if os(iOS) || os(macOS)
    private static func symbolWithAtos(objectPath: String, libraryAdress: String, callAddress: String) -> String {
        var symbol = Spawn.commandWithResult("/usr/bin/atos -o \(objectPath) -l \(libraryAdress) \(callAddress)")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if symbol.hasPrefix("atos cannot load") {
            return ""
        } else if symbol.hasPrefix("Invalid connection: com.apple.coresymbolicationd\n") {
            symbol = String(symbol.dropFirst("Invalid connection: com.apple.coresymbolicationd\n".count))
        }
        return symbol
    }
#endif

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
}

@_silgen_name("swift_demangle")
public
func _stdlib_demangleImpl(
    mangledName: UnsafePointer<CChar>?,
    mangledNameLength: UInt,
    outputBuffer: UnsafeMutablePointer<CChar>?,
    outputBufferSize: UnsafeMutablePointer<UInt>?,
    flags: UInt32
) -> UnsafeMutablePointer<CChar>?
