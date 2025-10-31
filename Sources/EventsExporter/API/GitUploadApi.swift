//
//  GitUploadApi.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 28/10/2025.
//

import Foundation

protocol GitUploadApi: APIService {
    func searchCommits(repositoryURL: String, commits: [String],
                       _ response: @escaping (Result<[String], APICallError>) -> Void)
    
    func uploadPackFile(file: URL, commit: String, repositoryURL: String,
                        _ response: @escaping (Result<Void, APICallError>) -> Void)
    
    func uploadPackFile(name: String, data: Data, commit: String, repositoryURL: String,
                        _ response: @escaping (Result<Void, HTTPClient.RequestError>) -> Void)
    
    func uploadPackFiles(directory: URL, commit: String, repositoryURL: String,
                         _ response: @escaping (Result<Void, APICallError>) -> Void)
}

extension GitUploadApi {
    func uploadPackFile(file: URL, commit: String, repositoryURL: String,
                        _ response: @escaping (Result<Void, APICallError>) -> Void)
    {
        do {
            let data = try Data(contentsOf: file, options: [.mappedIfSafe])
            uploadPackFile(name: file.lastPathComponent, data: data,
                           commit: commit, repositoryURL: repositoryURL)
            {
                response($0.mapError(APICallError.init))
            }
        } catch {
            response(.failure(.fileSystem(error)))
            return
        }
    }
    
    func uploadPackFiles(directory: URL, commit: String, repositoryURL: String,
                         _ response: @escaping (Result<Void, APICallError>) -> Void)
    {
        let files: [URL]
        do {
            files = try FileManager.default
                .contentsOfDirectory(at: directory,
                                     includingPropertiesForKeys: [.isRegularFileKey, .canonicalPathKey])
                .filter { $0.pathExtension == "pack" }
        } catch {
            response(.failure(.fileSystem(error)))
            return
        }
        uploadNextFile(index: 0, files: files, commit: commit, repositoryURL: repositoryURL, response)
    }
    
    private func uploadNextFile(index: Int, files: [URL], commit: String, repositoryURL: String,
                                _ response: @escaping (Result<Void, APICallError>) -> Void)
    {
        guard index < files.count else {
            response(.success(()))
            return
        }
        uploadPackFile(file: files[index], commit: commit, repositoryURL: repositoryURL) { result in
            switch result {
            case .success(_):
                self.uploadNextFile(index: index+1, files: files, commit: commit,
                                    repositoryURL: repositoryURL, response)
            case .failure(let err): response(.failure(err))
            }
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
    
    func searchCommits(repositoryURL: String, commits: [String],
                       _ response: @escaping (Result<[String], APICallError>) -> Void)
    {
        let meta = CommitRequestMeta(repositoryUrl: repositoryURL)
        let request = commits.map { APIData<CommitRequestMeta, Commit>(id: $0) }
        let log = self.log
        log.debug("Search commits request: [meta: \(meta), data: \(request)]")
        httpClient.call(CommitsCall.self,
                        url: endpoint.searchCommitsURL,
                        meta: meta, data: request,
                        headers: headers + [.contentTypeHeader(contentType: .applicationJSON)],
                        coders: (encoder, decoder))
        {
            log.debug("Search commits response: \($0)")
            response($0.map { $0.data.map { $0.id! } })
        }
    }
    
    func uploadPackFile(name: String, data: Data, commit: String, repositoryURL: String,
                        _ response: @escaping (Result<Void, HTTPClient.RequestError>) -> Void)
    {
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
        httpClient.send(request: request) {
            log.debug("Packfile upload response: \($0)")
            response($0.map { _ in })
        }
    }
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
