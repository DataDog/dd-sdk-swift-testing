/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

internal import EventsExporter
import Foundation

final class GitUploader {
    private static let packFilesLocation = "packfiles/v1/"
    private static let uploadedCommitFile = "uploaded_commits.json"

    private let gitDirectory: String
    private let log: Logger
    private let api: GitUploadApi
    private let unshallowEnabled: Bool
    private let telemetry: Telemetry?

    private let commitFolder: Directory
    private let packFilesDirectory: Directory

    init?(log: Logger, api: GitUploadApi, gitDirectory: String,
          commitFolder: Directory?, unshallowEnabled: Bool = true,
          telemetry: Telemetry? = nil)
    {
        guard !gitDirectory.isEmpty,
              let commitFolder = commitFolder,
              let packFilesDir = try? commitFolder.createSubdirectory(path: Self.packFilesLocation)
        else {
            log.print("GitUploader failed initializing")
            return nil
        }
        self.gitDirectory = gitDirectory
        self.api = api
        self.unshallowEnabled = unshallowEnabled
        self.telemetry = telemetry
        self.packFilesDirectory = packFilesDir
        self.commitFolder = commitFolder
        self.log = log
    }
    
    deinit {
        try? packFilesDirectory.delete()
    }
    
    func sendGitInfo(repositoryURL: URL?, commit: String) async -> Bool {
        guard !commitFolder.hasFile(named: Self.uploadedCommitFile) else {
            log.debug("GitUploader: git information alredy uploaded")
            return true
        }

        let repository: String
        if let url = repositoryURL {
            repository = url.spanAttribute
        } else {
            guard let rURL = gitTimed("ls-remote --get-url", command: .getRepository),
                  let pURL = URL(string: rURL) else {
                log.print("sendGitInfo failed, repository URL not found")
                return false
            }
            repository = pURL.spanAttribute
        }

        guard var newCommits = await searchForNewCommits(repositoryURL: repository) else {
            log.print("Can't obtain new commits")
            return false
        }
        log.debug("New commits: \(newCommits)")

        guard let commitsFile = try? commitFolder.createFile(named: Self.uploadedCommitFile) else {
            log.print("Can't create commits file")
            return false
        }
        if newCommits.isEmpty {
            saveCommits(file: commitsFile, commits: newCommits)
            return true
        }

        /// Check if the repository is a shallow clone, if so fetch more info and calculate one more time
        switch (isShallowRepository, unshallowEnabled) {
        case (true, true):
            let unshallowed = log.measure(name: "handleShallowClone") {
                handleShallowClone()
            }
            if unshallowed {
                guard let newCommitsUnshallow = await searchForNewCommits(repositoryURL: repository) else {
                    log.print("Can't obtain new commits after unshallow")
                    try? commitsFile.delete()
                    return false
                }
                log.debug("New commits after unshallow: \(newCommitsUnshallow)")
                if newCommitsUnshallow.isEmpty {
                    saveCommits(file: commitsFile, commits: newCommitsUnshallow)
                    return true
                }
                newCommits = newCommitsUnshallow
            }
        case (true, false):
            log.debug("Shallow repository detected but unshallow is disabled. Proceeding with available commits.")
        default: break
        }

        // Generate pack files for the new commits
        guard let directory = generatePackFilesFromCommits(commits: newCommits, repository: repository) else {
            try? commitsFile.delete()
            return false
        }

        // Report pack file count before upload
        if let telemetry {
            let packFileCount = (try? FileManager.default.contentsOfDirectory(atPath: directory.url.path))
                .map { $0.filter { $0.hasSuffix(".pack") }.count } ?? 0
            telemetry.metrics.gitRequests.objectsPackFiles.record(Double(packFileCount))
        }

        // Upload pack files for the new commits
        do {
            try await log.measure(name: "uploadExistingPackfiles") { () async throws(APICallError) in
                try await api.uploadPackFiles(directory: directory.url,
                                              commit: commit,
                                              repositoryURL: repository,
                                              observer: telemetry?.gitObjectsPackRequestObserver)
            }
        } catch {
            let err = LibraryConfigurationCommunicationError(
                requestName: "PackFileRequest",
                payload: "commit: \(commit)",
                error: error
            )
            log.print("packfiles upload failed: \(err)")
            try? commitsFile.delete()
            try? directory.delete()
            return false
        }

        try? directory.delete()
        saveCommits(file: commitsFile, commits: newCommits)
        return true
    }
    
    static func statusUpToDate(gitDirectory: String, log: Logger) -> Bool {
        guard !gitDirectory.isEmpty else {
            return false
        }
        guard let status = Spawn.output(try: #"git -c safe.directory="\#(gitDirectory)" -C "\#(gitDirectory)" status --short -uno"#, log: log) else {
            return false
        }
        log.debug("Git status: \(status)")
        return status.isEmpty
    }
    
    private func searchForNewCommits(repositoryURL: String) async -> [String]? {
        guard let latestCommits = log.measure(name: "getLatestCommits", getLatestCommits),
              !latestCommits.isEmpty else
        {
            log.print("sendGitInfo failed, can't get latest commits")
            return nil
        }
        let existingCommits: [String]
        do {
            existingCommits = try await log.measure(name: "searchRepositoryCommits") { () async throws(APICallError) in
                try await api.searchCommits(repositoryURL: repositoryURL,
                                            commits: latestCommits,
                                            observer: telemetry?.gitSearchCommitsRequestObserver)
            }
        } catch {
            let err = LibraryConfigurationCommunicationError(
                requestName: "SearchCommitsRequest",
                payload: "commits: \(latestCommits)",
                error: error
            )
            log.print("\(err)")
            return nil
        }
        let commits = Set(latestCommits).subtracting(existingCommits)
        if commits.isEmpty { return [] }
        return log.measure(name: "getCommitsAndTrees") {
            getCommitsAndTrees(included: Array(commits), excluded: existingCommits)
        }
    }
    
    private var isShallowRepository: Bool {
        // Check if is a shallow repository
        guard let isShallow = gitTimed("rev-parse --is-shallow-repository", command: .checkShallow) else {
            return false
        }
        log.debug("isShallow: \(isShallow)")
        return isShallow == "true"
    }
    
    private func handleShallowClone() -> Bool {
        guard let remote = git("config --default origin --get clone.defaultRemoteName") else {
            return false
        }
        
        if let head = git("rev-parse HEAD"), let result = unshallow(remote, head) {
            log.debug("Unshallow Result: \(result)")
            return true
        }
        
        if let head = git("rev-parse --abbrev-ref --symbolic-full-name @{upstream}"),
           let result = unshallow(remote, head)
        {
            log.debug("Unshallow Result: \(result)")
            return true
        }
        
        if let result = unshallow(remote, nil) {
            log.debug("Unshallow Result: \(result)")
            return true
        }
        
        return false
    }
    
    private func saveCommits(file: File, commits: [String]) {
        if let data = try? JSONEncoder().encode(commits) {
            try? file.append(data: data)
        }
    }
    
    private func git(_ cmd: String) -> String? {
        Spawn.output(try: "git -c safe.directory=\"\(gitDirectory)\" -C \"\(gitDirectory)\" \(cmd)", log: log)
    }

    /// Runs `body`, records `git.command` + `git.commandMs`, and on failure
    /// records `git.commandErrors` with the real exit code. Returns `nil` on failure.
    @discardableResult
    private func recordedGitCommand<T>(_ command: Telemetry.GitCommand,
                                        cmd: String,
                                        _ body: () throws -> T) -> T? {
        let start = Date()
        do {
            let result = try body()
            let ms = Date().timeIntervalSince(start) * 1000
            telemetry?.metrics.git.command.add(command: command)
            telemetry?.metrics.git.commandMs.record(ms, command: command)
            return result
        } catch let err as Spawn.RunError {
            let ms = Date().timeIntervalSince(start) * 1000
            log.debug("Command \(cmd) failed: \(err)")
            telemetry?.metrics.git.command.add(command: command)
            telemetry?.metrics.git.commandMs.record(ms, command: command)
            telemetry?.metrics.git.commandErrors.add(command: command, exitCode: err.exitCode)
            return nil
        } catch {
            let ms = Date().timeIntervalSince(start) * 1000
            log.debug("Command \(cmd) failed: \(error)")
            telemetry?.metrics.git.command.add(command: command)
            telemetry?.metrics.git.commandMs.record(ms, command: command)
            telemetry?.metrics.git.commandErrors.add(command: command, exitCode: 1)
            return nil
        }
    }

    @discardableResult
    private func gitTimed(_ cmd: String, command: Telemetry.GitCommand) -> String? {
        let fullCmd = "git -c safe.directory=\"\(gitDirectory)\" -C \"\(gitDirectory)\" \(cmd)"
        return recordedGitCommand(command, cmd: fullCmd) { try Spawn.output(fullCmd) }
    }

    private func getLatestCommits() -> [String]? {
        gitTimed(#"log --format=%H -n 1000 --since="1 month ago""#, command: .getLocalCommits)?.components(separatedBy: .newlines)
    }

    private func getCommitsAndTrees(included: [String], excluded: [String]) -> [String]? {
        let incl = included.joined(separator: " ")
        let excl = excluded.map { "^\($0)" }.joined(separator: " ")

        let cmd = """
        rev-list --objects --no-object-names --filter=blob:none \
        --since="1 month ago" \(excl) \(incl)
        """
        Log.debug("rev-list command: \(cmd)")

        guard let missingCommits = gitTimed(cmd, command: .getObjects) else {
            return nil
        }
        Log.debug("rev-list result: \(missingCommits)")

        return missingCommits.components(separatedBy: .newlines)
    }

    private func unshallow(_ remote: String, _ head: String?) -> String? {
        let cmd = """
        fetch --shallow-since="1 month ago" --update-shallow --filter="blob:none" \
        --recurse-submodules=no \(remote)\(head.map{" "+$0} ?? "")
        """
        return gitTimed(cmd, command: .unshallow)
    }

    private func generatePackFilesFromCommits(commits: [String], repository: String) -> Directory? {
        let generate = { (gitDir: String, dir: String, list: String) in
            do {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            } catch {
                return false
            }
            let cmd = """
            git -c safe.directory="\(gitDir)" -C "\(gitDir)" pack-objects --quiet --compression=9 --max-pack-size=3m "\(dir)" <<< "\(list)"
            """
            guard let _ = self.recordedGitCommand(.packObjects, cmd: cmd, {
                let (_, stderr) = try Spawn.command(cmd)
                if let stderr, stderr.contains("fatal:") {
                    throw Spawn.RunError.code(1, "", stderr)
                }
            }) else {
                try? FileManager.default.removeItem(atPath: dir)
                return false
            }
            return true
        }

        return log.measure(name: "packObjects") {
            var uploadPackfileDirectory = packFilesDirectory.url.path + "/" + UUID().uuidString + "/"
            let commitList = commits.joined(separator: "\n")

            if generate(gitDirectory, uploadPackfileDirectory, commitList) {
                return Directory(url: URL(fileURLWithPath: uploadPackfileDirectory, isDirectory: true))
            }

            log.debug("Can't write packfile to cache path. Trying to git directory...")

            uploadPackfileDirectory = gitDirectory + "/" + UUID().uuidString + "/"
            if generate(gitDirectory, uploadPackfileDirectory, commitList) {
                return Directory(url: URL(fileURLWithPath: uploadPackfileDirectory, isDirectory: true))
            }

            log.debug("packfile generation failed")
            return nil
        }
    }
}
