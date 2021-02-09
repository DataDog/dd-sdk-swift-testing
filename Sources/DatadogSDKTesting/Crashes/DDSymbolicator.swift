/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

struct DDSymbolicator {
    private static let crashLineRegex = try! NSRegularExpression(pattern: "^([0-9]+)([ \t]+)([^ \t]+)([ \t]+)(0x[0-9a-fA-F]+)([ \t]+)(0x[0-9a-fA-F]+)([ \t]+\\+[ \t]+[0-9]+)$?", options: .anchorsMatchLines)

    static func symbolicate(crashLog: String) -> String {
        return symbolicateCrash(crashLog: crashLog, dSYMFiles: locateDSYMFiles())
    }

    private static func locateDSYMFiles() -> [URL] {
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
    }

    private static func symbolicateCrash(crashLog: String, dSYMFiles: [URL]) -> String {
        var lines: [String] = crashLog.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        for i in 0 ..< lines.count {
            let line = lines[i]
            if let match = crashLineRegex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) {
                guard let libraryRange = Range(match.range(at: 3), in: line),
                    let libraryAddressRange = Range(match.range(at: 7), in: line),
                    let callAddressRange = Range(match.range(at: 5), in: line) else {
                    continue
                }

                let library = String(line[libraryRange])
                let libraryAddress = String(line[libraryAddressRange])
                let callAddress = String(line[callAddressRange])

                guard let dsym = dSYMFiles.first(where: { $0.lastPathComponent == library }) else {
                    // No dSYM to symbolicate this line, write symbol Information
                    var info = Dl_info()
                    guard let floatAdress = Float64(callAddress),
                        let ptr = UnsafeRawPointer(bitPattern: UInt(floatAdress)) else {
                        continue
                    }
                    let result = dladdr(ptr, &info)
                    if result != 0 {
                        let symbolName = info.dli_sname != nil ? demangleName(String(cString: info.dli_sname)) : ""
                        lines[i] = crashLineRegex.replacementString(for: match, in: line, offset: 0, template: "$1$2$3$4$5$6\(symbolName)")
                    }
                    continue
                }
                let symbol = Spawn.commandWithResult("/usr/bin/atos -o \(dsym.path) -l \(libraryAddress) \(callAddress)")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if symbol.isEmpty {
                    continue
                }
                lines[i] = crashLineRegex.replacementString(for: match, in: line, offset: 0, template: "$1$2$3$4$5$6\(symbol)")
            }
        }
        return lines.joined(separator: "\n")
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
