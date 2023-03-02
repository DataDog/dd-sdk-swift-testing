/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

struct CodeOwnerEntry {
    var path: String
    var codeowners: [String]
}

struct CodeOwners {
    var section = [String: [CodeOwnerEntry]]()

    init?(workspacePath: URL) {
        // Search on the possible locations CODEOWNER can exist
        var location = workspacePath.appendingPathComponent("CODEOWNERS")
        if !FileManager.default.fileExists(atPath: location.path) {
            location = workspacePath.appendingPathComponent(".github").appendingPathComponent("CODEOWNERS")
            if !FileManager.default.fileExists(atPath: location.path) {
                location = workspacePath.appendingPathComponent(".gitlab").appendingPathComponent("CODEOWNERS")
                if !FileManager.default.fileExists(atPath: location.path) {
                    location = workspacePath.appendingPathComponent(".docs").appendingPathComponent("CODEOWNERS")
                    if !FileManager.default.fileExists(atPath: location.path) {
                        return nil
                    }
                }
            }
        }

        guard let codeOwnersContent = try? String(contentsOf: location) else {
            return nil
        }

        self.init(content: codeOwnersContent)
    }

    init(content: String) {
        // Parse all lines that include information
        var currentSectionName = "[empty]"
        content.components(separatedBy: .newlines).forEach {
            let line = $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                return
            }

            if line.hasPrefix("["), line.hasSuffix("]") {
                let sectionName = String(String(line.dropFirst()).dropLast()).lowercased()
                if !sectionName.isEmpty {
                    currentSectionName = sectionName
                }
                return
            }

            let lineComponents = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            let owners = lineComponents.dropFirst()
            if let path = lineComponents.first,
               !owners.isEmpty
            {
                var currentSection = section[currentSectionName]
                if currentSection == nil {
                    section[currentSectionName] = [CodeOwnerEntry]()
                    currentSection = section[currentSectionName]
                }
                section[currentSectionName]?.append(CodeOwnerEntry(path: path, codeowners: owners.map { String($0) }))
            }
        }
    }

    func ownersForPath(_ path: String) -> String? {
        var totalCodeowners = [String]()
        for section in section.values {
            for owner in section.reversed() {
                if codeOwnersWildcard(path, pattern: owner.path) {
                    totalCodeowners += owner.codeowners
                    break
                }
            }
        }

        if totalCodeowners.isEmpty {
            return nil
        } else {
            return "[\"" + totalCodeowners.joined(separator: "\",\"") + "\"]"
        }
    }

    private func codeOwnersWildcard(_ string: String, pattern: String) -> Bool {
        var finalPattern: String = pattern

        let includesAnythingBefore: Bool
        let includesAnythingAfter: Bool

        if pattern.hasPrefix("/") {
            includesAnythingBefore = false
        } else {
            if finalPattern.hasPrefix("*") {
                finalPattern = String(finalPattern.dropFirst())
            }
            includesAnythingBefore = true
        }

        if pattern.hasSuffix("/") {
            includesAnythingAfter = true
        } else if pattern.hasSuffix("/*") {
            includesAnythingAfter = true
            finalPattern = String(finalPattern.dropLast())
        } else {
            includesAnythingAfter = false
        }

        if includesAnythingAfter {
            var found = true
            if includesAnythingBefore {
                found = string.contains(finalPattern)
            } else {
                found = string.hasPrefix(finalPattern)
            }
            guard found else {
                return false
            }
            if !pattern.hasSuffix("/*") {
                return true
            } else {
                if let patternEnd = string.range(of: finalPattern)?.upperBound {
                    let remainingString = string[patternEnd...]
                    return remainingString.firstIndex(of: "/") == nil
                }
                return false
            }

        } else {
            if includesAnythingBefore {
                return string.hasSuffix(finalPattern)
            }
            return string == finalPattern
        }
    }
}
