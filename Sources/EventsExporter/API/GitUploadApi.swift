/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal protocol GitUploadApi: APIService {
    func searchCommits(repositoryURL: String, commits: [String]) async throws(APICallError) -> [String]

    func uploadPackFile(file: URL, commit: String, repositoryURL: String) async throws(APICallError)

    func uploadPackFile(name: String, data: Data, commit: String,
                        repositoryURL: String) async throws(HTTPClient.RequestError)

    func uploadPackFiles(directory: URL, commit: String, repositoryURL: String) async throws(APICallError)
}

extension GitUploadApi {
    func uploadPackFile(file: URL, commit: String, repositoryURL: String) async throws(APICallError) {
        let data: Data
        do {
            data = try Data(contentsOf: file, options: [.mappedIfSafe])
        } catch {
            throw APICallError.fileSystem(error)
        }
        do {
            try await uploadPackFile(name: file.lastPathComponent, data: data,
                                     commit: commit, repositoryURL: repositoryURL)
        } catch {
            throw APICallError(from: error)
        }
    }

    func uploadPackFiles(directory: URL, commit: String, repositoryURL: String) async throws(APICallError) {
        let files: [URL]
        do {
            files = try FileManager.default
                .contentsOfDirectory(at: directory,
                                     includingPropertiesForKeys: [.isRegularFileKey, .canonicalPathKey])
                .filter { $0.pathExtension == "pack" }
        } catch {
            throw APICallError.fileSystem(error)
        }
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for file in files {
                    group.addTask {
                        try await uploadPackFile(file: file, commit: commit, repositoryURL: repositoryURL)
                    }
                }
                return try await group.next()
            }
        } catch let err as APICallError {
            throw err
        } catch {
            throw .unknownError(error)
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

    func searchCommits(repositoryURL: String, commits: [String]) async throws(APICallError) -> [String] {
        let meta = CommitRequestMeta(repositoryUrl: repositoryURL)
        let request = commits.map { APIData<CommitRequestMeta, Commit>(id: $0) }
        let log = self.log
        log.debug("Search commits request: [meta: \(meta), data: \(request)]")
        let response = try await httpClient.call(CommitsCall.self,
                                                 url: endpoint.searchCommitsURL,
                                                 meta: meta, data: request,
                                                 headers: headers + [.contentTypeHeader(contentType: .applicationJSON)],
                                                 coders: (encoder, decoder))
        log.debug("Search commits response: \(response.data)")
        return response.data.map { $0.id! }
    }

    func uploadPackFile(name: String, data: Data, commit: String,
                        repositoryURL: String) async throws(HTTPClient.RequestError)
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
        let _ = try await httpClient.send(request: request)
        log.debug("Packfile upload succeeded for \(name)")
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
