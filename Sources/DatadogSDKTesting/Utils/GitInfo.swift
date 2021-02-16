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
    private(set) var committerName: String?
    private(set) var committerEmail: String?

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

        if let commitInfo = try? self.findCommit(gitFolder: gitFolder, commit: commit) {
            commitMessage = commitInfo.fullMessage
            authorName = commitInfo.authorName
            authorEmail = commitInfo.authorEmail
            committerName = commitInfo.committerName
            committerEmail = commitInfo.committerEmail
        }
    }

    private func findCommit(gitFolder: URL, commit: String) throws -> CommitInfo {
        let index = commit.index(commit.startIndex, offsetBy: 2)
        let folder = commit[..<index]
        let filename = commit[index...]
        let commitObject = gitFolder.appendingPathComponent("objects")
            .appendingPathComponent(String(folder))
            .appendingPathComponent(String(filename))
        let objectContent = try Data(contentsOf: commitObject).zlibDecompress()
        let gitObject = try GitObject(objectContent: objectContent)
        return try parseCommit(gitFolder: gitFolder, gitObject: gitObject)
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
    var committerName: String?
    var committerEmail: String?
    var fullMessage: String?

    init(content: String) {
        let lines = content.components(separatedBy: CharacterSet(charactersIn: "\n")).filter { !$0.isEmpty }
        for line in lines {
            if line.hasPrefix("author ") {
                let author = line.dropFirst(7).components(separatedBy: CharacterSet(charactersIn: "<>"))
                guard author.count >= 2 else {
                    return
                }
                authorName = author[0].trimmingCharacters(in: .whitespaces)
                authorEmail = author[1].trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("committer ") {
                let committer = line.dropFirst(10).components(separatedBy: CharacterSet(charactersIn: "<>"))
                guard committer.count >= 2 else {
                    return
                }
                committerName = committer[0].trimmingCharacters(in: .whitespaces)
                committerEmail = committer[1].trimmingCharacters(in: .whitespaces)
            } else if authorName != nil, committerName != nil {
                fullMessage = line.trimmingCharacters(in: .whitespaces)
            }
        }
    }
}
