/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@_implementationOnly import EventsExporter
import Foundation

final class GitUploader {
    private static let packFilesLocation = "packfiles/v1/"
    private static let uploadedCommitFile = "uploaded_commits.json"
    
    private let workspacePath: String
    private let log: Logger
    private let exporter: EventsExporterProtocol
    
    private let commitFolder: Directory
    private let packFilesDirectory: Directory
    
    init?(log: Logger, exporter: EventsExporterProtocol, workspace: String, commitFolder: Directory?) {
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
    
    deinit {
        try? packFilesDirectory.delete()
    }
    
    func sendGitInfo(repositoryURL: URL?, commit: String) -> Bool {
        let repository: String
        if let url = repositoryURL {
            repository = url.spanAttribute
        } else {
            guard let rURL = git("ls-remote --get-url"), let pURL = URL(string: rURL) else {
                log.print("sendGitInfo failed, repository URL not found")
                return false
            }
            repository = pURL.spanAttribute
        }
        
        guard var newCommits = searchForNewCommits(repositoryURL: repository) else {
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
        if isShallowRepository {
            let unshallowed = log.measure(name: "handleShallowClone") {
                handleShallowClone()
            }
            if unshallowed {
                guard let newCommitsUnshallow = searchForNewCommits(repositoryURL: repository) else {
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
        }
        
        // Generate pack files for the new commits
        guard let directory = generatePackFilesFromCommits(commits: newCommits, repository: repository) else {
            try? commitsFile.delete()
            return false
        }
        
        // Upload pack files for the new commits
        do {
            try log.measure(name: "uploadExistingPackfiles") {
                try exporter.uploadPackFiles(packFilesDirectory: directory, commit: commit, repository: repository)
            }
        } catch {
            log.print("packfiles upload failed: \(error)")
            try? commitsFile.delete()
            try? directory.delete()
            return false
        }
        
        try? directory.delete()
        saveCommits(file: commitsFile, commits: newCommits)
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
    
    private func searchForNewCommits(repositoryURL: String) -> [String]? {
        guard let latestCommits = log.measure(name: "getLatestCommits", getLatestCommits),
              !latestCommits.isEmpty else
        {
            log.print("sendGitInfo failed, can't get latest commits")
            return nil
        }
        let existingCommits = log.measure(name: "searchRepositoryCommits") {
            exporter.searchCommits(repositoryURL: repositoryURL, commits: latestCommits)
        }
        let commits = Set(latestCommits).subtracting(existingCommits)
        if commits.isEmpty { return [] }
        return log.measure(name: "getCommitsAndTrees") {
            getCommitsAndTrees(included: Array(commits), excluded: existingCommits)
        }
    }
    
    private var isShallowRepository: Bool {
        // Check if is a shallow repository
        guard let isShallow = git("rev-parse --is-shallow-repository") else {
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
        Spawn.output(try: "git -C \"\(workspacePath)\" \(cmd)", log: log)
    }

    private func getLatestCommits() -> [String]? {
        git(#"log --format=%H -n 1000 --since="1 month ago""#)?.components(separatedBy: .newlines)
    }
    
    private func getCommitsAndTrees(included: [String], excluded: [String]) -> [String]? {
        let incl = included.joined(separator: " ")
        let excl = excluded.map { "^\($0)" }.joined(separator: " ")
        
        let cmd = """
        rev-list --objects --no-object-names --filter=blob:none \
        --since="1 month ago" \(excl) \(incl)
        """
        Log.debug("rev-list command: \(cmd)")
        
        guard let missingCommits = git(cmd) else {
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
        return git(cmd)
    }

    private func generatePackFilesFromCommits(commits: [String], repository: String) -> Directory? {
        let generate = { (ws: String, dir: String, list: String) in
            do {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            } catch {
                return false
            }
            let cmd = """
            git -C "\(ws)" pack-objects --quiet --compression=9 --max-pack-size=3m "\(dir)" <<< "\(list)"
            """
            guard let (_, err) = Spawn.command(try: cmd, log: self.log), !err.contains("fatal:") else {
                try? FileManager.default.removeItem(atPath: dir)
                return false
            }
            return true
        }
        
        return log.measure(name: "packObjects") {
            var uploadPackfileDirectory = packFilesDirectory.url.path + "/" + UUID().uuidString
            let commitList = commits.joined(separator: "\n")
            
            if generate(workspacePath, uploadPackfileDirectory, commitList) {
                return Directory(url: URL(fileURLWithPath: uploadPackfileDirectory, isDirectory: true))
            }
            
            log.debug("Can't write packfile to cache path. Trying to workspace...")
            
            uploadPackfileDirectory = workspacePath + "/" + UUID().uuidString
            if generate(workspacePath, uploadPackfileDirectory, commitList) {
                return Directory(url: URL(fileURLWithPath: uploadPackfileDirectory, isDirectory: true))
            }
            
            log.debug("packfile generation failed")
            return nil
        }
    }
}
