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
    
    private let workspacePath: String
    private let log: Logger
    private let api: GitUploadApi
    
    private let commitFolder: Directory
    private let packFilesDirectory: Directory
    
    init?(log: Logger, api: GitUploadApi, workspace: String, commitFolder: Directory?) {
        guard !workspace.isEmpty,
              let commitFolder = commitFolder,
              let packFilesDir = try? commitFolder.createSubdirectory(path: Self.packFilesLocation)
        else {
            log.print("GitUploader failed initializing")
            return nil
        }
        self.workspacePath = workspace
        self.api = api
        
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
    
    func sendGitInfo(repositoryURL: URL?, commit: String) -> AsyncResult<Void, GitError> {
        let repository: Result<String, GitError>
        if let url = repositoryURL {
            repository = .success(url.spanAttribute)
        } else {
            repository = git("ls-remote --get-url").flatMap { sUrl in
                guard let pUrl = URL(string: sUrl) else {
                    return .failure(.cannotParseRepositoryURL(sUrl))
                }
                return .success(pUrl.spanAttribute)
            }
        }
        
        return repository.async().flatMap { repository in
            // Search commits for the current repository
            self.searchForNewCommits(repositoryURL: repository).map { (repository, $0) }
        }
        .mapResult {
            $0.breakable((String, [String]).self)
            .flatMap { (repository, newCommits) in
                self.log.debug("New commits: \(newCommits)")
                if newCommits.isEmpty {
                    return .break((repository, newCommits))
                }
                return .success((repository, newCommits))
            }
            .breakFlatMap { (repository, newCommits) in
                self.isShallowRepository.map { (repository, newCommits, $0) }
            }
            .flatMap { (repository, newCommits, isShallow) in
                isShallow ? .success((repository, newCommits)) : .break((repository, newCommits))
            }
            .breakFlatMap { (repository, newCommits) in
                self.log.measure(name: "handle shallow clone") {
                    self.handleShallowClone().map { (repository, newCommits) }
                }
            }.breakResult()
        }
        .flatMap { (repository, _) in
            self.searchForNewCommits(repositoryURL: repository).map { (repository, $0) }
        }.flatMapResult {
            $0.breakable([String].self)
            .flatMap { (repository, newCommits) in
                newCommits.isEmpty ? .break(newCommits)
                                   : .success((repository, newCommits))
            }.breakFlatMap { (repository, newCommits) in
                self.generatePackFilesFromCommits(commits: newCommits, repository: repository)
                    .map { (repository, newCommits, $0) }
            }.async().breakFlatMap { (repository, newCommits, directory) in
                self.log.measureAsync(name: "upload pack files") {
                    self.api.uploadPackFiles(directory: directory.url, commit: commit, repositoryURL: repository)
                        .mapError { GitError.server($0) }
                        .mapResult { upload in Result { try directory.delete() }.mapError(GitError.init).flatMap { upload } }
                        .map { newCommits }
                }
            }.breakResult()
        }.flatMap { newCommits in
            // Create temp file to store commits
            Result { try self.commitFolder.createFile(named: Self.uploadedCommitFile) }
                .mapError(GitError.init)
                .flatMap { self.saveCommits(file: $0, commits: newCommits) } // save commits
                .async()
        }
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
    
    private func searchForNewCommits(repositoryURL: String) -> AsyncResult<[String], GitError> {
        let latest = self.log.measure(name: "get latest commits", self.getLatestCommits)
            .flatMap { $0.isEmpty ? .failure(.emptyServerResponse) : .success($0) }
        return latest.async().flatMap { latestCommits in
            self.log.measureAsync(name: "search repository commits") {
                self.api.searchCommits(repositoryURL: repositoryURL, commits: latestCommits)
            }.mapError { .server($0) }.map { (latestCommits, $0) }
        }.mapResult { $0.flatMap { (latestCommits, existingCommits) in
            let commits = Set(latestCommits).subtracting(existingCommits)
            if commits.isEmpty { return .success([]) }
            return self.log.measure(name: "get commits and trees") {
                self.getCommitsAndTrees(included: Array(commits), excluded: existingCommits)
            }
        } }
    }
    
    private var isShallowRepository: Result<Bool, GitError> {
        // Check if is a shallow repository
        let isShallow = git("rev-parse --is-shallow-repository")
        log.debug("isShallow: \(isShallow)")
        return isShallow.map { $0 == "true" }
    }
    
    private func handleShallowClone() -> Result<Void, GitError> {
        let remote: String
        switch git("config --default origin --get clone.defaultRemoteName") {
        case .failure(let err): return .failure(err)
        case .success(let rem): remote = rem
        }
        return git("rev-parse HEAD")
            .flatMapError { err in
                log.debug("\(err)")
                return .failure(err)
            }
            .flatMap { unshallow(remote, $0) }
            .flatMapError { err in
                log.debug("\(err)")
                return git("rev-parse --abbrev-ref --symbolic-full-name @{upstream}")
            }
            .flatMap { unshallow(remote, $0) }
            .flatMapError { err in
                log.debug("\(err)")
                return unshallow(remote, nil)
            }.map { _ in }
    }
    
    private func saveCommits(file: File, commits: [String]) -> Result<Void, GitError> {
        do {
            let data = try api.encoder.encode(commits)
            try file.append(data: data)
            return .success(())
        } catch {
            return .failure(GitError(error))
        }
    }
    
    private func git(_ cmd: String) -> Result<String, GitError> {
        do {
            return try .success(Spawn.output("git -C \"\(workspacePath)\" \(cmd)"))
        } catch {
            return .failure(.command("git -C \"\(workspacePath)\" \(cmd)", error))
        }
    }
    
    private func getLatestCommits() -> Result<[String], GitError> {
        git(#"log --format=%H -n 1000 --since="1 month ago""#).map { $0.components(separatedBy: .newlines) }
    }
    
    private func getCommitsAndTrees(included: [String], excluded: [String]) -> Result<[String], GitError> {
        let incl = included.joined(separator: " ")
        let excl = excluded.map { "^\($0)" }.joined(separator: " ")
        
        let cmd = """
        rev-list --objects --no-object-names --filter=blob:none \
        --since="1 month ago" \(excl) \(incl)
        """
        log.debug("rev-list command: \(cmd)")
        
        let missingCommits = git(cmd)
        log.debug("rev-list result: \(missingCommits)")
        
        return missingCommits.map { $0.components(separatedBy: .newlines) }
    }
    
    private func unshallow(_ remote: String, _ head: String?) -> Result<String, GitError> {
        let cmd = """
        fetch --shallow-since="1 month ago" --update-shallow --filter="blob:none" \
        --recurse-submodules=no \(remote)\(head.map{" "+$0} ?? "")
        """
        return git(cmd)
    }
    
    private func generatePackFilesFromCommits(commits: [String], repository: String) -> Result<Directory, GitError> {
        let gitCall = { (cmd: String) -> Result<(String, String), GitError> in
            do {
                let (out, err) = try Spawn.command("git -C \"\(self.workspacePath)\" \(cmd)")
                return .success((out!, err!))
            } catch {
                return .failure(.command("git -C \"\(self.workspacePath)\" \(cmd)", error))
            }
        }
        
        let generate = { (dir: String, list: String) -> Result<Void, GitError> in
            let cmd = #"pack-objects --quiet --compression=9 --max-pack-size=3m "\#(dir)" <<< "\#(list)""#
            return Result { try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true) }
                .mapError(GitError.init)
                .flatMap { gitCall(cmd) }
                .flatMap { (_, err) -> Result<Void, GitError> in
                    err.contains("fatal:") ? .failure(.packfileError(command: cmd, response: err)) : .success(())
                }
                .flatMapError { err in
                    Result { try FileManager.default.removeItem(atPath: dir) }
                        .mapError(GitError.init)
                        .flatMap { .failure(err) }
                }
        }
        
        return log.measure(name: "packObjects") {
            var uploadPackfileDirectory = packFilesDirectory.url.path + "/" + UUID().uuidString
            let commitList = commits.joined(separator: "\n")
            
            return generate(uploadPackfileDirectory, commitList).map {
                Directory(url: URL(fileURLWithPath: uploadPackfileDirectory, isDirectory: true))
            }.flatMapError { err in
                log.debug("Can't write packfile to cache path. Trying to workspace. Error: \(err)")
                uploadPackfileDirectory = workspacePath + "/" + UUID().uuidString
                return generate(uploadPackfileDirectory, commitList).map {
                    Directory(url: URL(fileURLWithPath: uploadPackfileDirectory, isDirectory: true))
                }
            }
        }
    }
    
    enum GitError: Error {
        case emptyServerResponse
        case cannotParseRepositoryURL(String)
        case server(APICallError)
        case request(HTTPClient.RequestError)
        case command(String, any Error)
        case packfileError(command: String, response: String)
        case other(any Error)
        
        init(_ error: any Error) {
            if let err = error as? Self {
                self = err
            }
            self = .other(error)
        }
    }
}

