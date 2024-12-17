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
        let locations = [
            workspacePath.appendingPathComponent("CODEOWNERS", isDirectory: false),
            workspacePath
                .appendingPathComponent(".github", isDirectory: true)
                .appendingPathComponent("CODEOWNERS", isDirectory: false),
            workspacePath
                .appendingPathComponent(".gitlab", isDirectory: true)
                .appendingPathComponent("CODEOWNERS", isDirectory: false),
            workspacePath
                .appendingPathComponent(".docs", isDirectory: true)
                .appendingPathComponent("CODEOWNERS", isDirectory: false)
        ]
        let fm = FileManager.default
        guard let location = locations.first(where: { fm.fileExists(atPath: $0.path) }) else {
            return nil
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
                var currentSection = section[currentSectionName] ?? []
                currentSection.append(CodeOwnerEntry(path: path, codeowners: owners.map { String($0) }))
                section[currentSectionName] = currentSection
            }
        }
    }

    func ownersForPath(_ path: String) -> String? {
        let fullPath = path.first == "/" ? path : "/" + path
        let codeowners = section.values.reduce(into: []) { (res, section) in
            section.last { codeOwnersWildcard(fullPath, pattern: $0.path) }.map {
                res.append(contentsOf: $0.codeowners)
            }
        }
        return codeowners.isEmpty ? nil : "[\"" + codeowners.joined(separator: "\",\"") + "\"]"
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
