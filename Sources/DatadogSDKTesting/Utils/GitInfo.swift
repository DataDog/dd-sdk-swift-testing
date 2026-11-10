/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

struct GitInfo {
    private(set) var commit: String
    private(set) var workspacePath: String
    private(set) var repository: String?
    private(set) var branch: String?
    private(set) var tag: String?
    private(set) var commitMessage: String?
    private(set) var authorName: String?
    private(set) var authorEmail: String?
    private(set) var authorDate: String?
    private(set) var committerName: String?
    private(set) var committerEmail: String?
    private(set) var committerDate: String?

    init?(workingDirectory: String, log: Logger) {
        let quote = { (value: String) -> String in
            "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        let directory = quote(workingDirectory)
        let git = { (arguments: String) -> String? in
            Spawn.output(try: "git -c safe.directory=\(directory) -C \(directory) \(arguments)", log: log)
        }
        guard let root = git("rev-parse --show-toplevel"),
              let metadata = git("log --no-show-signature --encoding=UTF-8 -1 --format='%H%x00%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI%x00%B' HEAD") else {
            return nil
        }
        let fields = metadata.components(separatedBy: "\0")
        guard fields.count == 8 else { return nil }
        let sha = fields[0]
        commit = sha
        workspacePath = root
        var localBranch = git("symbolic-ref --quiet HEAD").flatMap {
            $0.hasPrefix("refs/heads/") ? String($0.dropFirst("refs/heads/".count)) : nil
        }
        let isDetached = localBranch == nil
        if isDetached, let gitDirectory = git("rev-parse --absolute-git-dir"),
           let records = FetchHeadRecord.from(file: URL(fileURLWithPath: gitDirectory).appendingPathComponent("FETCH_HEAD")) {
            let branches = Set(records.filter { $0.commit == sha && $0.type == "branch" }.map(\.ref))
            localBranch = branches.count == 1 ? branches.first : nil
        }
        let trackingRemote = localBranch.flatMap { git("config --get " + quote("branch.\($0).remote")) }
        repository = trackingRemote.flatMap { $0 == "." ? nil : git("remote get-url " + quote($0)) }
        if repository == nil {
            let remotes = git("remote")?.components(separatedBy: .newlines).filter { !$0.isEmpty } ?? []
            let remote = remotes.contains("origin") ? "origin" : (remotes.count == 1 ? remotes[0] : nil)
            repository = remote.flatMap { git("remote get-url " + quote($0)) }
        }
        branch = localBranch
        if isDetached {
            let tags = git("tag --no-column --points-at HEAD")?.components(separatedBy: .newlines).filter { !$0.isEmpty } ?? []
            tag = tags.count == 1 ? tags[0] : nil
        }
        authorName = fields[1]
        authorEmail = fields[2]
        authorDate = fields[3]
        committerName = fields[4]
        committerEmail = fields[5]
        committerDate = fields[6]
        commitMessage = fields[7].trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

extension GitInfo {
    struct FetchHeadRecord {
        let commit: String
        let modifier: String?
        let type: String?
        let ref: String
        let info: String
        
        init?(line: String) {
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 3 else { return nil }
            let refInfo = parts[2]
            guard let refStart = refInfo.firstIndex(of: "'"),
                  let refEnd = refInfo.range(of: "' of ", range: refInfo.index(after: refStart)..<refInfo.endIndex)?.lowerBound else { return nil }
            commit = parts[0]
            modifier = parts[1].count > 0 ? parts[1] : nil
            type = refStart > refInfo.startIndex ?
                refInfo[..<refStart].trimmingCharacters(in: .whitespaces) : nil
            ref = String(refInfo[refInfo.index(after: refStart)..<refEnd])
            info = String(refInfo[refInfo.index(after: refEnd)...])
        }
        
        static func from(file url: URL) -> [Self]? {
            (try? String(contentsOf: url)).map { Self.from(contents: $0) }
        }
        
        static func from(contents string: String) -> [Self] {
            string.components(separatedBy: .newlines).compactMap { .init(line: $0) }
        }
    }
}
