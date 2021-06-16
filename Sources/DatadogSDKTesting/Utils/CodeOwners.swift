//
//  CodeOwner.swift
//  DatadogSDKTesting
//
//  Created by Ignacio Bonafonte Arruga on 15/6/21.
//

import Foundation

struct CodeOwnerEntry {
    var path: String
    var codeowners: String
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

            let owners = lineComponents.dropFirst().joined(separator: " ")
            if let path = lineComponents.first,
               !owners.isEmpty
            {
                ownerEntries.append(CodeOwnerEntry(path: path, codeowners: owners))
            }
        }
    }

    func ownersForPath(_ path: String) -> String? {
        for owner in ownerEntries.reversed() {
            if codeOwnersWildcard(path, pattern: owner.path) {
                return owner.codeowners
            }
        }
        return nil
    }

    private func codeOwnersWildcard(_ string: String, pattern: String) -> Bool {
        var finalPattern: String

        if pattern.hasPrefix("*") || pattern.hasPrefix("/") {
            finalPattern = pattern
        } else {
            finalPattern = "*" + pattern
        }

        if pattern.hasSuffix("/") {
            finalPattern += "*"
        }
        let matches = genericWildcard(string, pattern: finalPattern)

        if matches, pattern.hasSuffix("/*"), genericWildcard(string, pattern: finalPattern + "/*") {
            return false
        }

        return matches
    }

    private func genericWildcard(_ string: String, pattern: String) -> Bool {
        let pred = NSPredicate(format: "self LIKE %@", pattern)
        return !NSArray(object: string).filtered(using: pred).isEmpty
    }
}
