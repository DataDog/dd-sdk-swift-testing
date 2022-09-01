/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

@_implementationOnly import EventsExporter
import Foundation

struct GitUploader {
    let packFilesLocation = "com.datadog.civisibility/packfiles/v1/" + UUID().uuidString
    var packFilesdirectory: Directory

    let workspacePath: String

    init() throws {
        guard let envWorkspacePath = DDTestMonitor.env.workspacePath else {
            Log.debug("IntelligentTestRunner failed building")
            throw InternalError(description: "IntelligentTestRunner failed building")
        }
        packFilesdirectory = try Directory(withSubdirectoryPath: packFilesLocation)
        workspacePath = envWorkspacePath
    }

    func sendGitInfo() {
        let repo = getRepositoryURL()
        guard !repo.isEmpty else {
            Log.print("sendGitInfo failed, repository not found")
            return
        }

        let existingCommits = searchRepositoryCommits(repository: repo)
        Log.debug("Existing commits: \(existingCommits)")

        let commitsToUpload = getCommitsAndTreesExcluding(excluded: existingCommits)
        Log.debug("Commits To Upload: \(commitsToUpload)")

        guard !commitsToUpload.isEmpty else { return }
        generatePackFilesFromCommits(commits: commitsToUpload)

        uploadExistingPackfiles(repository: repo)
    }

    func statusUpToDate() -> Bool {
        let status = Spawn.commandWithResult(#"git -C "\#(workspacePath)" status --short -uno"#).trimmingCharacters(in: .whitespacesAndNewlines)
        Log.debug("Git status: \(status)")
        return status.isEmpty
    }

    private func getRepositoryURL() -> String {
        let url = Spawn.commandWithResult(#"git -C "\#(workspacePath)" config --get remote.origin.url"#).trimmingCharacters(in: .whitespacesAndNewlines)
        return url
    }

    private func getLatestCommits() -> [String] {
        let latestCommits = Spawn.commandWithResult(#"git -C "\#(workspacePath)" rev-list --objects --no-object-names --filter=blob:none HEAD --since="1 month ago""#).trimmingCharacters(in: .whitespacesAndNewlines)

        let commitsArray = latestCommits.components(separatedBy: .newlines)
        return commitsArray
    }

    private func searchRepositoryCommits(repository: String) -> [String] {
        let commits = getLatestCommits()

        return DDTestMonitor.tracer.eventsExporter?.searchCommits(repositoryURL: repository, commits: commits) ?? []
    }

    private func getCommitsAndTreesExcluding(excluded: [String]) -> [String] {
        let exclusionList = excluded.map { "^\($0)" }.joined(separator: " ")
        let missingCommits = Spawn.commandWithResult(#"git -C "\#(workspacePath)" rev-list --objects --no-object-names --filter=blob:none HEAD --since="1 month ago" \#(exclusionList)"#).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !missingCommits.isEmpty else { return [] }
        let missingCommitsArray = missingCommits.components(separatedBy: .newlines)
        return missingCommitsArray
    }

    private func generatePackFilesFromCommits(commits: [String]) {
        let commitList = commits.joined(separator: "\n")
        Spawn.command(#"git -C "\#(workspacePath)" pack-objects --quiet --compression=9 --max-pack-size=3m "\#(packFilesdirectory.getURL().path + "/" + UUID().uuidString)" <<< "\#(commitList)""#)
    }

    private func uploadExistingPackfiles(repository: String) {
        guard let commit = DDTestMonitor.env.commit else { return }
        DDTestMonitor.tracer.eventsExporter?.uploadPackFiles(packFilesDirectory: packFilesdirectory, commit: commit, repository: repository)
    }
}
