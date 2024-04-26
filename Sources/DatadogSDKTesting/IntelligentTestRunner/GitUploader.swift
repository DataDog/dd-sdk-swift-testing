/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@_implementationOnly import EventsExporter
import Foundation

struct GitUploader {
    private static let packFilesLocation = "packfiles/v1/"
    private static let uploadedCommitFile = "uploaded_commits.json"
    
    private let workspacePath: String
    private let log: Logger
    private let exporter: EventsExporter
    
    private let commitFolder: Directory
    private let packFilesDirectory: Directory

    init?(log: Logger, exporter: EventsExporter, workspace: String, commitFolder: Directory?) {
        guard !workspace.isEmpty,
              let commitFolder = commitFolder,
              let packFilesDir = try? commitFolder.createSubdirectory(path: Self.packFilesLocation)
        else {
            log.print("GitUploader failed initializing")
            return nil
        }
        self.workspacePath = workspace
        self.exporter = exporter
        
        guard !commitFolder.hasFile(named: Self.uploadedCommitFile) else {
            log.debug("GitUploader: git information alredy uploaded")
            return nil
        }
        
        self.packFilesDirectory = packFilesDir
        self.commitFolder = commitFolder
        self.log = log
    }

    mutating func sendGitInfo(repositoryURL: String, commit: String) -> Bool {
        guard !repositoryURL.isEmpty else {
            log.print("sendGitInfo failed, repository not found")
            return false
        }
        log.measure(name: "handleShallowClone") {
            /// Check if the repository is a shallow clone, if so fetch more info
            let _ = handleShallowClone(repository: repositoryURL)
        }

        let existingCommits = log.measure(name: "searchRepositoryCommits") {
            searchRepositoryCommits(repository: repositoryURL) ?? []
        }
        log.debug("Existing commits: \(existingCommits)")

        let commitsToUpload = log.measure(name: "getCommitsAndTreesExcluding") {
            getCommitsAndTreesExcluding(excluded: existingCommits) ?? []
        }
        log.debug("Commits To Upload: \(commitsToUpload)")

        guard let commitFile = try? commitFolder.createFile(named: Self.uploadedCommitFile) else {
            return false
        }
        
        if !commitsToUpload.isEmpty {
            guard var directory = generatePackFilesFromCommits(commits: commitsToUpload, repository: repositoryURL) else {
                try? commitFile.delete()
                return false
            }
            do {
                try log.measure(name: "uploadExistingPackfiles") {
                    try exporter.uploadPackFiles(packFilesDirectory: directory, commit: commit, repository: repositoryURL)
                }
            } catch {
                log.print("packfiles upload failed: \(error)")
                try? directory.delete()
                try? commitFile.delete()
                return false
            }
        }
        
        if let commits = try? JSONEncoder().encode(commitsToUpload) {
            try? commitFile.append(data: commits)
        }
        return true
    }

    static func statusUpToDate(workspace: String, log: Logger) -> Bool {
        guard !workspace.isEmpty else {
            return false
        }
        guard let status = Spawn.output(try: #"git -C "\#(workspace)" status --short -uno"#, log: log) else {
            return false
        }
        log.debug("Git status: \(status)")
        return status.isEmpty
    }

    private func handleShallowClone(repository: String) -> Bool {
        // Check if is a shallow repository
        guard let isShallow = Spawn.output(
            try: #"git -C "\#(workspacePath)" rev-parse --is-shallow-repository"#, log: log
        ) else {
            return false
        }
        log.debug("isShallow: \(isShallow)")
        guard isShallow == "true" else {
            return true
        }

        // Count if number of returned lines is greater than 1
        guard let lineLength = Spawn.output(
            try: #"git -C "\#(workspacePath)" log --format=oneline -n 2"#, log: log
        ) else {
            return false
        }
        log.debug("lineLength: \(lineLength)")
        guard !lineLength.contains("\n") else {
            return true
        }
        
        // Fetch remaining tree info
        guard let configResult = Spawn.output(
            try: #"git -C "\#(workspacePath)" config remote.origin.partialclonefilter "blob:none""#, log: log
        ) else {
            return false
        }
        log.debug("configResult: \(configResult)")

        guard let unshallowResult = Spawn.output(
            try: #"git -C "\#(workspacePath)" fetch --shallow-since="1 month ago" --update-shallow --refetch"#, log: log
        ) else {
            return false
        }
        log.debug("unshallowResult: \(unshallowResult)")
        return true
    }

    private func getLatestCommits() -> [String]? {
        let latestCommits = Spawn.output(
            try: #"git -C "\#(workspacePath)" log --format=%H -n 1000 --since="1 month ago""#, log: log
        )
        return latestCommits?.components(separatedBy: .newlines)
    }

    private func searchRepositoryCommits(repository: String) -> [String]? {
        getLatestCommits().map { commits in
            exporter.searchCommits(repositoryURL: repository, commits: commits)
        }
    }

    private func getCommitsAndTreesExcluding(excluded: [String]) -> [String]? {
        let exclusionList = excluded.map { "^\($0)" }.joined(separator: " ")
        
        let revlistCommand = #"git -C "\#(workspacePath)" rev-list --objects --no-object-names --filter=blob:none HEAD --since="1 month ago" \#(exclusionList)"#
        let revlistCommandWithoutExclusion = #"git -C "\#(workspacePath)" rev-list --objects --no-object-names --filter=blob:none HEAD --since="1 month ago""#
        
        Log.debug("rev-list command: \(revlistCommand)")
        Log.debug("rev-list command without exclusion: \(revlistCommandWithoutExclusion)")
        
        guard let missingCommits = Spawn.output(try: revlistCommand, log: log) else {
            return nil
        }
        Log.debug("rev-list result: \(missingCommits)")
        
        guard let missingCommitsWithoutExclusion = Spawn.output(try: revlistCommandWithoutExclusion, log: log) else {
            return nil
        }
        Log.debug("rev-list result without exclusion: \(missingCommitsWithoutExclusion)")
        
        guard !missingCommits.isEmpty else { return [] }
        let missingCommitsArray = missingCommits.components(separatedBy: .newlines)
        return missingCommitsArray
    }

    private func generatePackFilesFromCommits(commits: [String], repository: String) -> Directory? {
        let generate = { (ws: String, dir: String, list: String) in
            do {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            } catch {
                return false
            }
            let cmd = #"git -C "\#(ws)" pack-objects --quiet --compression=9 --max-pack-size=3m "\#(dir)" <<< "\#(list)""#
            guard let (_, err) = Spawn.command(try: cmd, log: log) else {
                return false
            }
            return !err.contains("fatal:")
        }
        
        return log.measure(name: "packObjects") {
            var uploadPackfileDirectory = packFilesDirectory.url.path + "/" + UUID().uuidString
            let commitList = commits.joined(separator: "\n")
            
            if generate(workspacePath, uploadPackfileDirectory, commitList) {
                return Directory(url: URL(fileURLWithPath: uploadPackfileDirectory))
            }
            
            // Can't write to cache. Let's try to workspace folder
            uploadPackfileDirectory = workspacePath + "/" + UUID().uuidString
            if generate(workspacePath, uploadPackfileDirectory, commitList) {
                return Directory(url: URL(fileURLWithPath: uploadPackfileDirectory))
            }
            
            log.debug("packfile generation failed")
            return nil
        }
    }
}
