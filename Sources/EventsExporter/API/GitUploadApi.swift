//
//  GitUploadApi.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 28/10/2025.
//

import Foundation

public protocol GitUploadApi: APIService {
    func searchCommits(repositoryURL: String, commits: [String]) -> AsyncResult<[String], APICallError>
    
    func uploadPackFile(file: URL, commit: String, repositoryURL: String) -> AsyncResult<Void, APICallError>
    
    func uploadPackFile(name: String, data: Data, commit: String,
                        repositoryURL: String) -> AsyncResult<Void, HTTPClient.RequestError>
    
    func uploadPackFiles(directory: URL, commit: String, repositoryURL: String) -> AsyncResult<Void, APICallError>
}

extension GitUploadApi {
    func uploadPackFile(file: URL, commit: String, repositoryURL: String) -> AsyncResult<Void, APICallError> {
        do {
            let data = try Data(contentsOf: file, options: [.mappedIfSafe])
            return uploadPackFile(name: file.lastPathComponent, data: data,
                                  commit: commit, repositoryURL: repositoryURL).mapError(APICallError.init)
        } catch {
            return .error(.fileSystem(error))
        }
    }
    
    func uploadPackFiles(directory: URL, commit: String, repositoryURL: String) -> AsyncResult<Void, APICallError> {
        let files: [URL]
        do {
            files = try FileManager.default
                .contentsOfDirectory(at: directory,
                                     includingPropertiesForKeys: [.isRegularFileKey, .canonicalPathKey])
                .filter { $0.pathExtension == "pack" }
        } catch {
            return .error(.fileSystem(error))
        }
        return uploadNextFile(index: 0, files: files, commit: commit, repositoryURL: repositoryURL)
    }
    
    private func uploadNextFile(index: Int, files: [URL], commit: String, repositoryURL: String) -> AsyncResult<Void, APICallError>
    {
        guard index < files.count else { return .value(()) }
        return uploadPackFile(file: files[index], commit: commit, repositoryURL: repositoryURL).flatMap { _ in
            self.uploadNextFile(index: index+1, files: files, commit: commit, repositoryURL: repositoryURL)
        }
    }
}

struct GitUploadApiService: GitUploadApi {
    typealias CommitsCall = APICall<[APIData<CommitRequestMeta, Commit>], [APIDataNoMeta<Commit>]>
    
    var endpoint: Endpoint
    var headers: [HTTPHeader]
    var encoder: JSONEncoder
    var decoder: JSONDecoder
    let httpClient: HTTPClient
    let log: Logger
    
    init(config: APIServiceConfig, httpClient: HTTPClient, log: Logger) {
        self.endpoint = config.endpoint
        self.httpClient = httpClient
        self.log = log
        self.headers = config.defaultHeaders
        self.encoder = config.encoder
        self.decoder = config.decoder
    }
    
    func searchCommits(repositoryURL: String, commits: [String]) -> AsyncResult<[String], APICallError> {
        let meta = CommitRequestMeta(repositoryUrl: repositoryURL)
        let request = commits.map { APIData<CommitRequestMeta, Commit>(id: $0) }
        let log = self.log
        log.debug("Search commits request: [meta: \(meta), data: \(request)]")
        return httpClient.call(CommitsCall.self,
                        url: endpoint.searchCommitsURL,
                        meta: meta, data: request,
                        headers: headers + [.contentTypeHeader(contentType: .applicationJSON)],
                        coders: (encoder, decoder))
            .peek { log.debug("Search commits response: \($0)") }
            .map { $0.data.map { $0.id! }}
    }
    
    func uploadPackFile(name: String, data: Data, commit: String,
                        repositoryURL: String) -> AsyncResult<Void, HTTPClient.RequestError> {
        let log = self.log
        let meta = CommitRequestMeta(repositoryUrl: repositoryURL)
        let pushedSha = APIEnvelope<APIData<CommitRequestMeta, Commit>>(meta: meta, data: .init(id: commit))
        let pushedData: Data = try! encoder.encode(pushedSha)
        
        var request = MultipartFormURLRequest(url: endpoint.packfileURL)
        request.headers = headers
        request.append(data: data,
                       withName: "packfile",
                       filename: name,
                       contentType: .applicationOctetStream)
        request.append(data: pushedData,
                       withName: "pushedSha",
                       filename: name + ".json",
                       contentType: .applicationJSON)
        log.debug("Uploading packfile \(name) for commit \(commit)")
        return httpClient.send(request: request).peek {
            log.debug("Packfile upload response: \($0)")
        }.asVoid
    }
    
    var endpointURLs: Set<URL> { [endpoint.searchCommitsURL, endpoint.packfileURL] }
}

extension GitUploadApiService {
    struct Commit: APIAttributes, APIVoidValue, Codable {
        static var apiType: String = "commit"
        static var void: Self = .init()
    }
    
    struct CommitRequestMeta: Encodable {
        let repositoryUrl: String
    }
}

private extension Endpoint {
    var searchCommitsURL: URL {
        let endpoint = "/api/v2/git/repository/search_commits"
        switch self {
        case let .other(testsBaseURL: url, logsBaseURL: _): return url.appendingPathComponent(endpoint)
        default: return mainApi(endpoint: endpoint)!
        }
    }
    
    var packfileURL: URL {
        let endpoint = "/api/v2/git/repository/packfile"
        switch self {
        case let .other(testsBaseURL: url, logsBaseURL: _): return url.appendingPathComponent(endpoint)
        default: return mainApi(endpoint: endpoint)!
        }
    }
}
