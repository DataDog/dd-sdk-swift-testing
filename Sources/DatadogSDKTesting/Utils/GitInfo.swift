/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

struct GitInfo {
    private(set) var commit: String
    private(set) var workspacePath: String
    private(set) var repository: String?
    private(set) var branch: String?
    private(set) var commitMessage: String?
    private(set) var authorName: String?
    private(set) var authorEmail: String?
    private(set) var authorDate: String?
    private(set) var committerName: String?
    private(set) var committerEmail: String?
    private(set) var committerDate: String?

    init(gitFolder: URL) throws {
        workspacePath = gitFolder.deletingLastPathComponent().path
        let headPath = gitFolder.appendingPathComponent("HEAD")
        var mergePath: String?
        let head = try String(contentsOf: headPath)
        if head.hasPrefix("ref:") {
            mergePath = head.trimmingCharacters(in: .whitespacesAndNewlines)
            mergePath!.removeFirst(4)
            mergePath = mergePath!.trimmingCharacters(in: .whitespacesAndNewlines)
            self.branch = mergePath
            let refData = try String(contentsOf: gitFolder.appendingPathComponent(mergePath!))
            commit = refData.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let fetchHeadPath = gitFolder.appendingPathComponent("FETCH_HEAD")
            if let fetchHead = try? String(contentsOf: fetchHeadPath),
               let first = fetchHead.firstIndex(of: "'"),
               let last = fetchHead[fetchHead.index(after: first)...].firstIndex(of: "'")
            {
                let auxBranch = fetchHead[fetchHead.index(after: first) ... fetchHead.index(before: last)]
                if !auxBranch.isEmpty {
                    self.branch = String(auxBranch)
                }
            }
            commit = head.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let configPath = gitFolder.appendingPathComponent("config")
        let configs = getConfigItems(configPath: configPath)
        if configs.count > 0 {
            var remote = "origin"

            let branchItem = configs.first { $0.type == "branch" && $0.merge == branch }
            if let branchItem = branchItem {
                branch = branchItem.name
                remote = branchItem.remote ?? "origin"
            }

            let remoteItem = configs.first { $0.type == "remote" && $0.name == remote }
            if let remoteItem = remoteItem {
                repository = remoteItem.url
            }
        }

        if let commitInfo = try? findCommit(gitFolder: gitFolder, commit: commit) {
            commitMessage = commitInfo.fullMessage
            authorName = commitInfo.authorName
            authorEmail = commitInfo.authorEmail
            authorDate = ConvertGitTimeToISO8601(date: commitInfo.authorDate)
            committerName = commitInfo.committerName
            committerEmail = commitInfo.committerEmail
            committerDate = ConvertGitTimeToISO8601(date: commitInfo.committerDate)
        }
    }

    private func findCommit(gitFolder: URL, commit: String) throws -> CommitInfo {
        let index = commit.index(commit.startIndex, offsetBy: 2)
        let folder = commit[..<index]
        let filename = commit[index...]
        let commitObject = gitFolder.appendingPathComponent("objects")
            .appendingPathComponent(String(folder))
            .appendingPathComponent(String(filename))
        let objectContent: String
        if FileManager.default.fileExists(atPath: commitObject.path) {
            objectContent = try Data(contentsOf: commitObject).zlibDecompress()
            let gitObject = try GitObject(objectContent: objectContent)
            return try parseCommit(gitFolder: gitFolder, gitObject: gitObject)
        } else {
            return try getObjectFromPackFile(gitFolder: gitFolder, commit: commit)
        }
    }

    private func parseCommit(gitFolder: URL, gitObject: GitObject) throws -> CommitInfo {
        if gitObject.type.compare("tag", options: .caseInsensitive) == .orderedSame {
            guard let index = gitObject.content.firstIndex(of: "\n") else {
                throw InternalError(description: "Incorrect Git object")
            }
            let objectSha = gitObject.content[..<index]
            let shaChunks = objectSha.split(separator: " ")
            guard shaChunks.count >= 2 else {
                throw InternalError(description: "Incorrect Git object")
            }
            let sha = String(shaChunks[1])
            return try findCommit(gitFolder: gitFolder, commit: sha)
        } else {
            guard gitObject.type.compare("commit", options: .caseInsensitive) == .orderedSame else {
                throw InternalError(description: "Incorrect Git object")
            }
            return CommitInfo(content: gitObject.content)
        }
    }

    /// Recovers commit info from pack and idx files.
    /// Implemented based on: https://codewords.recurse.com/issues/three/unpacking-git-packfiles
    /// More references:
    /// https://git-scm.com/docs/pack-format#_object_types
    /// http://shafiul.github.io/gitbook/7_the_packfile.html
    /// http://driusan.github.io/git-pack.html
    private func getObjectFromPackFile(gitFolder: URL, commit: String) throws -> CommitInfo {
        let packFolder = gitFolder.appendingPathComponent("objects").appendingPathComponent("pack")

        var packOffset: UInt64
        var indexFile: URL
        (indexFile, packOffset) = try locateIndex(packFolder: packFolder, commit: commit)

        let packFile = indexFile.deletingPathExtension().appendingPathExtension("pack")
        let filehandler = try FileHandle(forReadingFrom: packFile)

        // check .pack version is 2
        let packHeaderData = filehandler.readData(ofLength: 8)
        if packHeaderData[4] != 0 || packHeaderData[5] != 0 || packHeaderData[6] != 0 || packHeaderData[7] != 2 {
            return CommitInfo(content: "")
        }

        filehandler.seek(toFileOffset: packOffset)

        var objectSize: Int
        let typeCommit = 1
        let typeTag = 4

        var packData = filehandler.readData(ofLength: 1)
        let type = (packData[0] & 0x70) >> 4
        guard type == typeCommit || type == typeTag else {
            return CommitInfo(content: "")
        }

        objectSize = Int(packData[0] & 0x0F)
        var multiplier = 16
        while packData[0] >= 128 {
            packData = filehandler.readData(ofLength: 1)
            objectSize += Int(packData[0] & 0x7F) * multiplier
            multiplier *= 128
        }

        packData = filehandler.readData(ofLength: objectSize)

        let decompressedString = packData.zlibDecompress(minimumSize: objectSize)
        if type == typeCommit {
            return CommitInfo(content: decompressedString)
        } else {
            // We will probably always receive only typeCommit, but tag is supported just in case
            let parts = decompressedString.components(separatedBy: " ")
            guard parts.count == 2 else {
                return CommitInfo(content: "")
            }
            let sha = parts[1]
            return try findCommit(gitFolder: gitFolder, commit: sha)
        }
    }

    /// This function returns the index file containing the commit sha (it there are more than one idx file in the folder,
    /// and the offset of this object in the pack file
    fileprivate func locateIndex(packFolder: URL, commit: String) throws -> (indexFile: URL, packOffset: UInt64) {
        var indexFile: URL?
        var packOffset: UInt64 = 0

        guard let commitAsData = Data(hex: commit) else {
            throw InternalError(description: "Incorrect Git object")
        }

        var indexFiles: [URL] = []
        if let enumerator = FileManager.default.enumerator(at: packFolder, includingPropertiesForKeys: nil) {
            for element in enumerator {
                if let file = element as? URL, file.pathExtension == "idx" {
                    indexFiles.append(file)
                }
            }
        }

        let index = commit.index(commit.startIndex, offsetBy: 2)
        let folder = commit[..<index]

        try indexFiles.forEach { file in
            // Index files has 4 or five different layers of information
            var indexData = try Data(contentsOf: file)
            // skip header
            indexData = indexData.advanced(by: 8)

            // First layer: 256 4-byte elements, with number of elements per folder
            guard let folderIndex = Int(folder, radix: 16) else {
                return
            }

            var numberOfObjectsInIndex: Int
            var numberOfPreviousObjects = 0
            let previousIndex = folderIndex > 0 ? folderIndex - 1 : folderIndex
            indexData = indexData.advanced(by: previousIndex * 4)
            var parser = BinaryParser(data: indexData.subdata(in: 0..<8))
            if folderIndex > 0 {
                numberOfPreviousObjects = Int(try parser.parseUInt32())
                numberOfObjectsInIndex = Int(try parser.parseUInt32()) - numberOfPreviousObjects
            } else {
                numberOfObjectsInIndex = Int(try parser.parseUInt32())
            }
            indexData = indexData.advanced(by: (255 - previousIndex) * 4)

            parser = BinaryParser(data: indexData.subdata(in: 0..<4))
            let totalNumberOfObjects = Int(try parser.parseUInt32())
            indexData = indexData.advanced(by: 4)

            // Second layer: 20-byte elements with the names in order
            indexData = indexData.advanced(by: 20 * Int(numberOfPreviousObjects))
            var indexOfCommit: Int?

            var startSearchIndex = indexData.startIndex
            let endSearchIndex = startSearchIndex.advanced(by: 20 * numberOfObjectsInIndex)
            while indexOfCommit == nil {
                if let range = indexData.range(of: commitAsData, options: [], in: Range(uncheckedBounds: (startSearchIndex, endSearchIndex))) {
                    // Check we are really at the start of a commit and are not finding the sha in between two others
                    if range.startIndex.isMultiple(of: 20) {
                        indexOfCommit = Int(numberOfPreviousObjects) + (startSearchIndex.distance(to: range.startIndex) / 20)
                    } else {
                        startSearchIndex = range.startIndex
                    }
                } else {
                    return
                }
            }

            guard let indexOfObject = indexOfCommit else {
                return
            }

            indexFile = file
            indexData = indexData.advanced(by: 20 * Int(totalNumberOfObjects - numberOfPreviousObjects))

            // Third layer: 4 byte CRC for each object
            indexData = indexData.advanced(by: 4 * Int(totalNumberOfObjects))

            // Fourth layer: 4 byte per object of offset in pack file
            indexData = indexData.advanced(by: 4 * Int(indexOfObject))
            parser = BinaryParser(data: indexData.subdata(in: 0..<4))
            var offset = try parser.parseUInt32()
            if offset & 0x80000000 == 0 {
                // offset is in this layes
                packOffset = UInt64(offset)
            } else {
                // offset is not in this layer, clear first bit and look at it at the 5th layer
                offset = offset & 0x7FFFFFFF
                indexData = indexData.advanced(by: 4 * Int(totalNumberOfObjects - indexOfObject))
                indexData = indexData.advanced(by: 8 * Int(offset))
                parser = BinaryParser(data: indexData.subdata(in: 0..<8))
                packOffset = try parser.parseUInt64()
            }
        }

        guard let desiredIndexFile = indexFile else {
            throw InternalError(description: "Incorrect Git object")
        }

        return (desiredIndexFile, packOffset)
    }

    private func ConvertGitTimeToISO8601(date: String?) -> String? {
        guard let date = date else { return nil }

        let components = date.components(separatedBy: " ")
        guard components.count >= 1,
              let timeInterval = TimeInterval(components[0]) else { return nil }

        let myDate = Date(timeIntervalSince1970: timeInterval)
        return ISO8601DateFormatter().string(from: myDate)
    }

    class ConfigItem {
        var type: String = ""
        var name: String = ""
        var url: String?
        var remote: String?
        var merge: String?

        init(type: String, name: String) {
            self.type = type
            self.name = name
        }
    }

    private func getConfigItems(configPath: URL) -> [ConfigItem] {
        var configItems = [ConfigItem]()
        let regex = try! NSRegularExpression(pattern: "^\\[(.*) \\\"(.*)\\\"\\]", options: .anchorsMatchLines)

        if let configData = try? String(contentsOf: configPath) {
            let configDataLines = configData.components(separatedBy: "\n")

            var currentItem: ConfigItem?

            configDataLines.forEach { line in
                if line.first == "\t", let currentItem = currentItem {
                    let parts = line.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if parts.count < 2 {
                        return
                    }
                    switch parts[0] {
                        case "url":
                            currentItem.url = parts[1]
                        case "remote":
                            currentItem.remote = parts[1]
                        case "merge":
                            currentItem.merge = parts[1]
                        default:
                            break
                    }
                    return
                }

                if let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)),
                   let firstRange = Range(match.range(at: 1), in: line),
                   let secondRange = Range(match.range(at: 2), in: line)
                {
                    if let currentItem = currentItem {
                        configItems.append(currentItem)
                    }

                    currentItem = ConfigItem(type: String(line[firstRange]),
                                             name: String(line[secondRange]))
                }
            }
        }

        return configItems
    }
}

struct GitObject {
    var type: String
    var size: Int
    var content: String

    init(objectContent: String) throws {
        guard let separator = objectContent.firstIndex(of: Character(UnicodeScalar(0))) else {
            throw InternalError(description: "Incorrect Git object")
        }
        let metadataBytes = objectContent[..<separator]
        let metadata = metadataBytes.split(separator: " ")
        guard metadata.count >= 2, let size = Int(metadata[1]) else {
            throw InternalError(description: "Incorrect Git object")
        }
        type = String(metadata[0])
        self.size = size
        content = String(objectContent[objectContent.index(after: separator)...])
    }
}

struct CommitInfo {
    var authorName: String?
    var authorEmail: String?
    var authorDate: String?
    var committerName: String?
    var committerEmail: String?
    var committerDate: String?
    var fullMessage: String?

    init(content: String) {
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        var message = ""
        var foundPGP = false
        for line in lines {
            if line.hasPrefix("author ") {
                let author = line.dropFirst(7).components(separatedBy: CharacterSet(charactersIn: "<>"))
                guard author.count >= 3 else {
                    return
                }
                authorName = author[0].trimmingCharacters(in: .whitespaces)
                authorEmail = author[1].trimmingCharacters(in: .whitespaces)
                authorDate = author[2].trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("committer ") {
                let committer = line.dropFirst(10).components(separatedBy: CharacterSet(charactersIn: "<>"))
                guard committer.count >= 3 else {
                    return
                }
                committerName = committer[0].trimmingCharacters(in: .whitespaces)
                committerEmail = committer[1].trimmingCharacters(in: .whitespaces)
                committerDate = committer[2].trimmingCharacters(in: .whitespaces)
            } else if authorName != nil, committerName != nil {
                if line.contains("--BEGIN PGP SIGNATURE--") || line.contains("--BEGIN SSH SIGNATURE--") {
                    foundPGP = true
                } else if line.contains("--END PGP SIGNATURE--") || line.contains("--END SSH SIGNATURE--") {
                    foundPGP = false
                } else if foundPGP == false {
                    if !message.isEmpty {
                        message += "\n"
                    }
                    let messageline = line.trimmingCharacters(in: .whitespaces)
                    if !messageline.isEmpty {
                        message += messageline
                    }
                }
            }
        }

        fullMessage = message
    }
}
