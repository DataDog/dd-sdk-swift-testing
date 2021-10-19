//
//  CodeOwner.swift
//  DatadogSDKTesting
//
//  Created by Ignacio Bonafonte Arruga on 15/6/21.
//

import Foundation

struct CodeOwnerEntry {
    var path: String
    var codeowners: [String]
}

struct CodeOwners {
    var ownerEntries = [CodeOwnerEntry]()

    init?(workspacePath: URL) {
        // Search on the possible locations CODEOWNER can exist
        var location = workspacePath.appendingPathComponent("CODEOWNERS")
        if !FileManager.default.fileExists(atPath: location.path) {
            location = workspacePath.appendingPathComponent(".github").appendingPathComponent("CODEOWNERS")
            if !FileManager.default.fileExists(atPath: location.path) {
                location = workspacePath.appendingPathComponent(".docs").appendingPathComponent("CODEOWNERS")
                if !FileManager.default.fileExists(atPath: location.path) {
                    return nil
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
        content.components(separatedBy: .newlines).forEach {
            let line = $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                return
            }
            let lineComponents = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            let owners = lineComponents.dropFirst()
            if let path = lineComponents.first,
               !owners.isEmpty
            {
                ownerEntries.append(CodeOwnerEntry(path: path, codeowners: owners.map { String($0) }))
            }
        }
    }

    func ownersForPath(_ path: String) -> String? {
        for owner in ownerEntries.reversed() {
            if codeOwnersWildcard(path, pattern: owner.path) {
                return "[\"" + owner.codeowners.joined(separator: "\",\"") + "\"]"
            }
        }
        return nil
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
