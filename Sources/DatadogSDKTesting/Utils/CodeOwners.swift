/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

struct CodeOwners {
    typealias SectionEntry = (path: NSRegularExpression, owners: [String], isNegated: Bool)
    typealias Section = (name: String, entries: Array<SectionEntry>)
    
    let sections: [Section]
    
    init(sections: [Section]) {
        self.sections = sections
    }
    
    init(workspacePath: URL) throws(ParsingError) {
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
                .appendingPathComponent("CODEOWNERS", isDirectory: false),
            workspacePath
                .appendingPathComponent("docs", isDirectory: true)
                .appendingPathComponent("CODEOWNERS", isDirectory: false)
        ]
        let fm = FileManager.default
        guard let location = locations.first(where: { fm.fileExists(atPath: $0.path) }) else {
            throw .codeOwnersFileNotFound
        }
        guard let codeOwnersContent = try? String(contentsOf: location) else {
            throw .cantReadFile(location)
        }
        try self.init(parsing: codeOwnersContent)
    }
    
    
    init(parsing content: String) throws(ParsingError) {
        var sections: [String: Array<SectionEntry>] = [:]
        var sectionsOrder: Array<String> = []
        let lines = content.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var index = Self._skipCommentLines(lines: lines, lineIndex: 0)
        var parsedEmptySection: Bool = false
        
        while index < lines.count {
            let line = lines[index]
            if let offset = try Self._isSectionHeader(line: line, index: index) {
                let section = try Self._parseSection(lines: lines, lineIndex: index, offset: offset)
                if sections[section.name] != nil {
                    sections[section.name]!.append(contentsOf: section.entries)
                } else {
                    sections[section.name] = section.entries
                    sectionsOrder.append(section.name)
                }
                index = section.index
            } else {
                guard !parsedEmptySection else {
                    throw .foundEmptySectionAfterRealSection(line, index)
                }
                let section = try Self._parseSection(named: "[]",
                                                     defaultOwners: [],
                                                     lines: lines,
                                                     lineIndex: index)
                sections["[]"] = section.entries
                sectionsOrder.append("[]")
                index = section.index
                parsedEmptySection = true
            }
        }
        self.init(sections: sectionsOrder.map { ($0, sections[$0]!) })
    }
    
    func ownersForPath(_ path: String) -> String? {
        let fullPath = path.first == "/" ? path : "/" + path
        // Last matching rule wins (across all sections). If it has empty owners, return [].
        // Negated patterns (!) exclude paths from their section; once excluded, cannot be included again.
        var codeowners: [String] = []
        for sectionEntries in sections {
            var lastMatch: [String]?
            var isExcluded = false
            for entry in sectionEntries.entries {
                if entry.path.firstMatch(in: fullPath, range: NSRange(location: 0, length: fullPath.count)) != nil {
                    if entry.isNegated {
                        isExcluded = true
                    } else if !isExcluded {
                        lastMatch = entry.owners
                    }
                }
            }
            if !isExcluded, let lastMatch {
                codeowners.append(contentsOf: lastMatch)
            }
        }
        guard !codeowners.isEmpty else { return nil }
        return "[\"" + codeowners.joined(separator: "\",\"") + "\"]"
    }
}

extension CodeOwners {
    enum ParsingError: Error {
        case codeOwnersFileNotFound
        case cantReadFile(URL)
        case cantFindClosingBracket(String, Int)
        case emptySectionName(String, Int)
        case foundEmptySectionAfterRealSection(String, Int)
        case patternError(String, String, Int)
        case patternRegexError(String, any Error, Int)
    }
}



private extension CodeOwners {
    struct SlidingWindow {
        let pattern: String
        private var index: String.Index
        private(set) var _0: Character?
        private(set) var _1: Character?
        private(set) var _2: Character?
        
        init(pattern: String) {
            self.pattern = pattern
            self.index = pattern.startIndex
            _0 = nil; _1 = nil; _2 = pattern[index]
            advance()
        }
        
        var isEnd: Bool { index == pattern.endIndex }
        
        mutating func advance(amount: Int = 1) {
            for _ in 0..<amount { _advance() }
        }
        
        private mutating func _advance() {
            self._0 = _1
            self._1 = _2
            if !isEnd {
                index = pattern.index(after: index)
            }
            self._2 = isEnd ? nil : pattern[index]
        }
    }
    
    static func _parseSection(named name: String, defaultOwners: [String],
                                      lines: [String], lineIndex: Int) throws(ParsingError) -> (entries: [SectionEntry], index: Int)
    {
        var index = _skipCommentLines(lines: lines, lineIndex: lineIndex)
        var entries: [SectionEntry] = []
        while index < lines.count {
            let line = lines[index]
            guard try _isSectionHeader(line: line, index: index) == nil else { // end of the section
                break
            }
            var record = try _parseOwnersRecord(line: line, lineIndex: index)
            if record.owners.isEmpty {
                record.owners = defaultOwners
            }
            entries.append(record)
            index = _skipCommentLines(lines: lines, lineIndex: index + 1)
        }
        return (entries, index)
    }
    
    static func _parseSection(lines: [String], lineIndex: Int, offset: Int) throws(ParsingError) -> (name: String, entries: [SectionEntry], index: Int) {
        let line = lines[lineIndex]
        let header = try _parseSectionHeader(from: line.suffix(from: line.index(line.startIndex, offsetBy: offset)), index: lineIndex)
        let section = try _parseSection(named: header.name, defaultOwners: header.owners, lines: lines, lineIndex: lineIndex + 1)
        return (name: header.name, entries: section.entries, index: section.index)
    }
    
    static func _isSectionHeader(line: String, index: Int) throws(ParsingError) -> Int? {
        switch line[line.startIndex] {
        case "[": return 1
        case "^" where line.count > 2 && line[line.index(after: line.startIndex)] == "[":
            return 2
        default: return nil
        }
    }
    
    static func _parseSectionHeader(from line: Substring, index: Int) throws(ParsingError) -> (name: String, owners: [String]) {
        guard let closeIndex = _firstUnescapedIndex(of: _headerEndSymbol, in: line) else {
            throw .cantFindClosingBracket(String(line), index)
        }
        let sectionName = String(line[line.startIndex..<closeIndex]).trimmingCharacters(in: .whitespaces)
        guard !sectionName.isEmpty else {
            throw .emptySectionName(String(line), index)
        }
        let ownersSubstring = line.suffix(from: line.index(after: closeIndex))
        let owners: [String]
        if let ownersStart = _firstUnescapedIndex(of: .whitespaces, in: ownersSubstring) {
            owners = _parseOwners(line: ownersSubstring.suffix(from: ownersSubstring.index(after: ownersStart)))
        } else {
            owners = []
        }
        return (sectionName.lowercased(), owners)
    }
    
    static func _parseOwnersRecord(line: String, lineIndex: Int) throws(ParsingError) -> SectionEntry {
        var pathPart: String
        let owners: [String]
        if let splitIndex = _firstUnescapedIndex(of: .whitespaces, in: Substring(line)) {
            owners = _parseOwners(line: line.suffix(from: line.index(after: splitIndex)))
            pathPart = line.prefix(upTo: splitIndex).trimmingCharacters(in: .whitespaces)
        } else {
            owners = []
            pathPart = line.trimmingCharacters(in: .whitespaces)
        }
        
        guard pathPart.count > 0 else {
            throw .patternError(line, "Pattern is empty after cleanup", lineIndex)
        }
        
        let isNegated: Bool = pathPart[pathPart.startIndex] == "!"
        if isNegated {
            pathPart = pathPart
                .suffix(from: pathPart.index(after: pathPart.startIndex))
                .trimmingCharacters(in: .whitespaces)
        }
        
        guard pathPart.count > 0 else {
            throw .patternError(line, "Negated pattern is empty after cleanup", lineIndex)
        }
        
        var window = SlidingWindow(
            pattern: pathPart // unescape path
                .replacingOccurrences(of: "\\\\", with: "\\")
                .replacingOccurrences(of: "\\ ", with: " ")
                .replacingOccurrences(of: "\\#", with: "#")
        )
        var pattern: String = ""
        var isFinished: Bool = false
        var hasFolderGlob: Bool = false
        
        while !isFinished {
            switch (window._0, window._1, window._2) {
            // Start of the path
            case (nil, "*", nil), (nil, "/", nil): // starts with / or *, 1 symbol
                pattern = ".*"
                window.advance(amount: 2)
            case (nil, .some(let char), nil): // one symbol. File named like that or folder
                pattern = "^.*?/\(_escapeRegex(char: char))(?:$|(?:/.*))"
                window.advance(amount: 2)
            case (nil, "/", _): // /something
                pattern = "^/"
                window.advance(amount: 2)
            case (nil, .some(_), .some(_)): // start of parsing
                pattern += "^.*?/"
                window.advance()
            // Inside the path
            case ("*", "*", "/"), ("*", "*", nil):
                pattern += ".*?"
                hasFolderGlob = true
                window.advance(amount: 3)
            case ("*", "*", .some(let char)):
                throw .patternError(window.pattern,
                                    "Unknown character \(char) after **. Expected / or last symbol",
                                    lineIndex)
            case ("*", _, _):
                pattern += "[^/]*"
                window.advance()
            // End of the path
            case ("/", "*", nil):
                pattern += "/[^/]+"
                window.advance(amount: 2)
            case (.some(let char), "/", nil):
                pattern += "\(_escapeRegex(char: char))/.*"
                window.advance(amount: 2)
            case (.some(let char), nil, nil): // end of the path without traling /
                pattern += _escapeRegex(char: char)
                // if it's not a glob treating like "path/", else like "path/*"
                let ext = hasFolderGlob ? "/[^/]*" : "/.*"
                // we check for exact path or for children of folder with this path
                pattern += "(?:$|(?:\(ext)))"
                window.advance()
            // Default char handler
            case (.some(let char), _, _):
                pattern += _escapeRegex(char: char)
                window.advance()
            // End of the parsing. Window is empty
            case (nil, nil, nil): isFinished = true
            // Something went wrong.
            default: throw .patternError(window.pattern, "Unexpected state: \(window)", lineIndex)
            }
        }
        pattern += "$"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            return (regex, owners, isNegated)
        } catch {
            throw .patternRegexError(line, error, lineIndex)
        }
    }
    
    static func _escapeRegex(char: Character) -> String {
        switch char {
        case ".", "+", "*", "?", "(", ")", "\\",
             "[", "]", "{", "}", "^", "$", "|":
            return "\\\(char)"
        default:
            return String(char)
        }
    }
    
    static func _parseOwners(line: Substring) -> [String] {
        var endIndex = line.endIndex
        if let commentIndex = _firstUnescapedIndex(of: _commentSymbols, in: line) {
            endIndex = commentIndex
        }
        return line.prefix(upTo: endIndex).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }
    
    static func _skipCommentLines(lines: [String], lineIndex: Int) -> Int {
        var lineIndex = lineIndex
        for line in lines[lineIndex...] {
            guard line.isEmpty || _commentSymbols.contains(line[line.startIndex]) else { break }
            lineIndex += 1
        }
        return lineIndex
    }
    
    static func _firstUnescapedIndex(of charSet: CharacterSet, in string: Substring) -> Substring.Index? {
        var prevIndex: Substring.Index = string.startIndex
        var currentSubstring = string
        var found: Bool = false
        while let subIndex = currentSubstring.firstIndex(where: { charSet.contains($0) }) {
            let offset = currentSubstring.distance(from: currentSubstring.startIndex, to: subIndex)
            guard offset > 0 else { return prevIndex }
            if currentSubstring[currentSubstring.index(before: subIndex)] == "\\" {
                prevIndex = string.index(prevIndex, offsetBy: offset + 1)
                currentSubstring = string.suffix(from: prevIndex)
            } else {
                prevIndex = string.index(prevIndex, offsetBy: offset)
                found = true
                break
            }
        }
        return found ? prevIndex : nil
    }
    
    static let _commentSymbols = CharacterSet(charactersIn: "#")
    static let _headerEndSymbol = CharacterSet(charactersIn: "]")
}

private extension CharacterSet {
    func contains(_ char: Character) -> Bool {
        char.unicodeScalars.allSatisfy { contains($0) }
    }
}
