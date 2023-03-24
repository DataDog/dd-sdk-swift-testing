/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@_implementationOnly import EventsExporter
import Foundation

struct GitUploader {
    private let gitCachePath = "git"
    private var gitUploadCacheFolder: Directory?

    static let workspacePath: String = DDTestMonitor.env.workspacePath ?? ""

    private let packFilesLocation = "packfiles/v1/" + UUID().uuidString
    var packFilesdirectory: Directory

    init?() {
        guard !GitUploader.workspacePath.isEmpty,
              let packFilesdirectory = try? DDTestMonitor.dataPath?.createSubdirectory(path: packFilesLocation)
        else {
            Log.debug("GitUploader failed initializing")
            return nil
        }

        gitUploadCacheFolder = try? DDTestMonitor.commitFolder?.subdirectory(path: gitCachePath)
        if gitUploadCacheFolder != nil {
            Log.debug("GitUploader: git information alredy uploaded")
            return nil
        }

        self.packFilesdirectory = packFilesdirectory
    }

    mutating func sendGitInfo() {
        let repo = DDTestMonitor.localRepositoryURLPath
        guard !repo.isEmpty else {
            Log.print("sendGitInfo failed, repository not found")
            return
        }
        Log.measure(name: "handleShallowClone") {
            /// Check if the repository is a shallow clone, if so fetch more info
            handleShallowClone(repository: repo)
        }

        var existingCommits = [String]()
        Log.measure(name: "searchRepositoryCommits") {
            existingCommits = searchRepositoryCommits(repository: repo)
        }
        Log.debug("Existing commits: \(existingCommits)")

        var commitsToUpload = [String]()
        Log.measure(name: "getCommitsAndTreesExcluding") {
            commitsToUpload = getCommitsAndTreesExcluding(excluded: existingCommits)
        }
        Log.debug("Commits To Upload: \(commitsToUpload)")

        gitUploadCacheFolder = try? DDTestMonitor.commitFolder?.createSubdirectory(path: gitCachePath)
        Log.runOnDebug({
            let commitsToUploadFile = try? gitUploadCacheFolder?.createFile(named: "commitsToUpload")
            try? commitsToUploadFile?.append(data: JSONEncoder().encode(commitsToUpload))
        }())

        guard !commitsToUpload.isEmpty else { return }
        generateAndUploadPackFilesFromCommits(commits: commitsToUpload, repository: repo)
    }

    static func statusUpToDate() -> Bool {
        guard !GitUploader.workspacePath.isEmpty else {
            return false
        }
        let status = Spawn.commandWithResult(#"git -C "\#(GitUploader.workspacePath)" status --short -uno"#).trimmingCharacters(in: .whitespacesAndNewlines)
        Log.debug("Git status: \(status)")
        return status.isEmpty
    }

    private func handleShallowClone(repository: String) {
        // Check if is a shallow repository
        let isShallow = Spawn.commandWithResult(#"git -C "\#(GitUploader.workspacePath)" rev-parse --is-shallow-repository"#).trimmingCharacters(in: .whitespacesAndNewlines)
        Log.debug("isShallow: \(isShallow)")
        if isShallow != "true" {
            return
        }

        // Count if number of returned lines is greater than 1
        let lineLength = Spawn.commandWithResult(#"git -C "\#(GitUploader.workspacePath)" log --format=oneline -n 2"#).trimmingCharacters(in: .whitespacesAndNewlines)
        Log.debug("lineLength: \(lineLength)")
        guard !lineLength.contains("\n") else {
            return
        }
        // Fetch remaining tree info
        let configResult = Spawn.commandWithResult(#"git -C "\#(GitUploader.workspacePath)" config remote.origin.partialclonefilter "blob:none""#)
        Log.debug("configResult: \(configResult)")

        let unshallowResult = Spawn.commandWithResult(#"git -C "\#(GitUploader.workspacePath)" fetch --shallow-since="1 month ago" --update-shallow --refetch"#)
        Log.debug("unshallowResult: \(unshallowResult)")
    }

    private func getLatestCommits() -> [String] {
        let latestCommits = Spawn.commandWithResult(#"git -C "\#(GitUploader.workspacePath)" log --format=%H -n 1000 --since="1 month ago""#).trimmingCharacters(in: .whitespacesAndNewlines)
        let commitsArray = latestCommits.components(separatedBy: .newlines)
        return commitsArray
    }

    private func searchRepositoryCommits(repository: String) -> [String] {
        let commits = getLatestCommits()
        return DDTestMonitor.tracer.eventsExporter?.searchCommits(repositoryURL: repository, commits: commits) ?? []
    }

    private func getCommitsAndTreesExcluding(excluded: [String]) -> [String] {
        let exclusionList = excluded.map { "^\($0)" }.joined(separator: " ")
        let missingCommits = Spawn.commandWithResult(#"git -C "\#(GitUploader.workspacePath)" rev-list --objects --no-object-names --filter=blob:none HEAD --since="1 month ago" \#(exclusionList)"#).trimmingCharacters(in: .whitespacesAndNewlines)
        Log.debug("rev-list objects: \(missingCommits)")
        guard !missingCommits.isEmpty else { return [] }
        let missingCommitsArray = missingCommits.components(separatedBy: .newlines)
        return missingCommitsArray
    }

    private func generateAndUploadPackFilesFromCommits(commits: [String], repository: String) {
        var uploadPackfileDirectory = packFilesdirectory
        Log.measure(name: "packObjects") {
            let commitList = commits.joined(separator: "\n")
            let aux = Spawn.commandWithResult(#"git -C "\#(GitUploader.workspacePath)" pack-objects --quiet --compression=9 --max-pack-size=3m "\#(packFilesdirectory.url.path + "/" + UUID().uuidString)" <<< "\#(commitList)""#)
            if aux.hasPrefix("fatal:") {
                let uploadPackfilePath = GitUploader.workspacePath + "/" + UUID().uuidString
                try? FileManager.default.createDirectory(atPath: uploadPackfilePath, withIntermediateDirectories: true)
                uploadPackfileDirectory = Directory(url: URL(fileURLWithPath: uploadPackfilePath))
                Spawn.command(#"git -C "\#(GitUploader.workspacePath)" pack-objects --quiet --compression=9 --max-pack-size=3m "\#(uploadPackfileDirectory.url.path + "/" + UUID().uuidString)" <<< "\#(commitList)""#)
            }
        }
        Log.measure(name: "uploadExistingPackfiles") {
            uploadExistingPackfiles(directory: uploadPackfileDirectory, repository: repository)
        }
        try? uploadPackfileDirectory.deleteAllFiles()
    }

    private func uploadExistingPackfiles(directory: Directory, repository: String) {
        guard let commit = DDTestMonitor.env.commit else { return }
        DDTestMonitor.tracer.eventsExporter?.uploadPackFiles(packFilesDirectory: packFilesdirectory, commit: commit, repository: repository)
    }
}
