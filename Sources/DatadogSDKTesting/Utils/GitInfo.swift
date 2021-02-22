/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
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
            let refData = try String(contentsOf: gitFolder.appendingPathComponent(mergePath!))
            commit = refData.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            commit = head.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let configPath = gitFolder.appendingPathComponent("config")
        if let configData = try? String(contentsOf: configPath) {
            let configDataLines = configData.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            var intoRemote = false
            var tmpBranch: String?

            configDataLines.forEach { line in
                if line.hasPrefix("[remote") {
                    intoRemote = line.contains("origin")
                    return
                }

                if self.branch == nil, line.hasPrefix("[branch") {
                    tmpBranch = line
                    tmpBranch?.removeFirst(9)
                    tmpBranch?.removeLast(2)
                    return
                }

                if line.contains("merge"), let equalIdx = line.firstIndex(of: "=") {
                    let mergeIdx = line.index(after: equalIdx)
                    let mergeData = line.suffix(from: mergeIdx).trimmingCharacters(in: .whitespacesAndNewlines)
                    if mergeData == mergePath {
                        self.branch = tmpBranch
                        return
                    }
                }

                if intoRemote, line.contains("url =") {
                    let splitArray = line
                        .components(separatedBy: "=")
                        .filter { !$0.isEmpty }
                    if splitArray.count == 2 {
                        repository = splitArray[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
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
            objectContent = try getObjectFromPackFile(gitFolder: gitFolder, commit: commit)
            return CommitInfo(content: objectContent)
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

    private func getObjectFromPackFile(gitFolder: URL, commit: String) throws -> String {
        let packFolder = gitFolder.appendingPathComponent("objects").appendingPathComponent("pack")

        var packOffset: UInt64
        var indexFile: URL
        (indexFile, packOffset) = try locateIndex(packFolder: packFolder, commit: commit)

        let packFile = indexFile.deletingPathExtension().appendingPathExtension("pack")
        let filehandler = try FileHandle(forReadingFrom: packFile)

        // check .pack version is 2
        let packHeaderData = filehandler.readData(ofLength: 8)
        if(  packHeaderData[4] != 0 || packHeaderData[5] != 0 || packHeaderData[6] != 0 || packHeaderData[7] != 2 ) {
            return ""
        }

        filehandler.seek(toFileOffset: packOffset)
        var objectSize: Int
        var packData = filehandler.readData(ofLength: 2)
        if packData[0] < 128 {
            objectSize = Int(packData[0] & 0x0F)
            packData = filehandler.readData(ofLength: objectSize)
        } else {
            objectSize = Int(UInt16(packData[1] & 0x7F) * 16 + UInt16(packData[0] & 0x0F))
            packData = filehandler.readData(ofLength: objectSize * 100)
        }
        return packData.zlibDecompress(minimumSize: objectSize)
    }

    /// This function returns the index file containing the commit sha (it there are more than one idx file in the folder,
    /// and the offset of this object in the pack file
    fileprivate func locateIndex(packFolder: URL, commit: String) throws -> (indexFile: URL, packOffset: UInt64) {
        var indexFile: URL?
        var packOffset: UInt64 = 0

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
            let folderIndex = Int(folder, radix: 16)!
            let previousIndex = folderIndex > 0 ? folderIndex - 1 : folderIndex
            indexData = indexData.advanced(by: previousIndex * 4)
            var parser = BinaryParser(data: indexData.subdata(in: 0..<8))
            let numberOfPreviousObjects = try parser.parseUInt32()
            let numberOfObjectsInIndex = (try parser.parseUInt32() - numberOfPreviousObjects)
            indexData = indexData.advanced(by: (255 - previousIndex) * 4)
            parser = BinaryParser(data: indexData.subdata(in: 0..<4))
            let totalNumberOfObjects = try parser.parseUInt32()
            indexData = indexData.advanced(by: 4)

            // Second layer: 20-byte elements with the names in order
            indexData = indexData.advanced(by: 20 * Int(numberOfPreviousObjects))
            var indexOfCommit: UInt32?
            for i in 0..<numberOfObjectsInIndex {
                let string = indexData.subdata(in: 0..<20).hexString
                if string.compare(commit, options: .caseInsensitive) == .orderedSame {
                    indexOfCommit = numberOfPreviousObjects + i
                    break
                } else {
                    indexData = indexData.advanced(by: 20)
                }
            }

            guard let indexOfObject = indexOfCommit else {
                return
            }

            indexFile = file
            indexData = indexData.advanced(by: 20 * Int(totalNumberOfObjects - indexOfObject))

            // Third layer: 4 byte CRC for each object
            indexData = indexData.advanced(by: 4 * Int(totalNumberOfObjects))

            // Fourth layer: 4 byte per object of offset in pack file
            indexData = indexData.advanced(by: 4 * Int(indexOfObject))
            parser = BinaryParser(data: indexData.subdata(in: 0..<4))
            var offset = try parser.parseUInt32()
            if offset & 0x8000000 == 0 {
                // offset is in this layes
                packOffset = UInt64(offset)
            } else {
                // offset is not in this layer, clear first bit and look at it at the 5th layer
                offset = offset & 0x7FFFFFFF
                indexData = indexData.advanced(by: 4 * Int(totalNumberOfObjects - indexOfObject))
                indexData = indexData.advanced(by: 8 * Int(indexOfObject))
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

        let components = date.components(separatedBy: CharacterSet(charactersIn: " "))
        guard components.count >= 1,
            let timeInterval = TimeInterval(components[0]) else { return nil }

        let myDate = Date(timeIntervalSince1970: timeInterval)
        return ISO8601DateFormatter().string(from: myDate)
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
        let lines = content.components(separatedBy: CharacterSet(charactersIn: "\n")).filter { !$0.isEmpty }
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
                fullMessage = line.trimmingCharacters(in: .whitespaces)
            }
        }
    }
}
