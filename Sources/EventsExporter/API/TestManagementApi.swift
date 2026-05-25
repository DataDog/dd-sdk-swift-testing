/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public protocol TestManagementApi: APIService {
    func tests(
        repositoryURL: String, sha: String?, commitMessage: String?, branch: String?, module: String?
    ) async throws(APICallError) -> TestManagementTestsInfo
}

public struct TestManagementTestsInfo: Codable {
    public let modules: [String: Module]

    public init(modules: [String : Module]) {
        self.modules = modules
    }

    public struct Module: Codable {
        public let suites: [String: Suite]

        public init(suites: [String : Suite]) {
            self.suites = suites
        }
    }

    public struct Suite: Codable {
        public let tests: [String: Test]

        public init(tests: [String : Test]) {
            self.tests = tests
        }
    }

    public struct Test: Codable {
        public let properties: Properties

        public init(properties: Properties) {
            self.properties = properties
        }

        public init() {
            self.init(properties: .init())
        }

        public init(disabled: Bool = false, quarantined: Bool = false, attemptToFix: Bool = false) {
            self.init(properties: .init(disabled: disabled,
                                        quarantined: quarantined,
                                        attemptToFix: attemptToFix))
        }
    }

    public struct Properties: Codable {
        public let disabled: Bool
        public let quarantined: Bool
        public let attemptToFix: Bool

        public init(disabled: Bool = false, quarantined: Bool = false, attemptToFix: Bool = false) {
            self.disabled = disabled
            self.quarantined = quarantined
            self.attemptToFix = attemptToFix
        }
    }
}

struct TestManagementApiService: TestManagementApi, APIServiceConstructible {
    typealias TestsCall = APICall<APIDataNoMeta<TestsRequest>, APIDataNoMeta<TestsResponse>>

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

    func tests(repositoryURL: String, sha: String?, commitMessage: String?,
               branch: String?, module: String?) async throws(APICallError) -> TestManagementTestsInfo
    {
        let request = TestsRequest(repositoryUrl: repositoryURL,
                                   commitMessage: commitMessage,
                                   module: module,
                                   branch: branch,
                                   sha: sha)
        let log = self.log
        log.debug("TestManagement tests request: \(request)")
        let response = try await httpClient.call(TestsCall.self,
                                                 url: endpoint.testManagementTestsURL,
                                                 data: .init(attributes: request),
                                                 headers: headers + [.contentTypeHeader(contentType: .applicationJSON)],
                                                 coders: (encoder, decoder))
        log.debug("TestManagement tests response: \(response.data.attributes)")
        return TestManagementTestsInfo(modules: response.data.attributes.modules)
    }

    var endpointURLs: Set<URL> { [endpoint.testManagementTestsURL] }
}

extension TestManagementApiService {
    struct TestsRequest: Encodable, APIAttributesUUID, CustomDebugStringConvertible {
        let repositoryUrl: String
        let commitMessage: String?
        let module: String?
        let branch: String?
        let sha: String?

        static var apiType: String = "ci_app_libraries_tests_request"

        var debugDescription: String {
            func opt(_ value: String?) -> String { value.map { #""\#($0)""# } ?? "null" }
            return #"{"repository_url": "\#(repositoryUrl)""#
                + #", "commit_message": \#(opt(commitMessage))"#
                + #", "module": \#(opt(module))"#
                + #", "branch": \#(opt(branch))"#
                + #", "sha": \#(opt(sha))}"#
        }
    }

    struct TestsResponse: Decodable, APIResponseAttributesHasType,
                          APIResponseAttributesBrokenId, CustomDebugStringConvertible
    {
        let modules: [String: TestManagementTestsInfo.Module]

        static var apiType: String = "ci_app_libraries_tests"

        var debugDescription: String {
            let entries = modules.map { name, mod in renderModule(name, mod) }
                .joined(separator: ", ")
            return #"{"modules": {\#(entries)}}"#
        }

        private func renderModule(_ name: String, _ mod: TestManagementTestsInfo.Module) -> String {
            let suites = mod.suites.map { renderSuite($0, $1) }.joined(separator: ", ")
            return #""\#(name)": {"suites": {\#(suites)}}"#
        }

        private func renderSuite(_ name: String, _ suite: TestManagementTestsInfo.Suite) -> String {
            let tests = suite.tests.map { renderTest($0, $1) }.joined(separator: ", ")
            return #""\#(name)": {"tests": {\#(tests)}}"#
        }

        private func renderTest(_ name: String, _ test: TestManagementTestsInfo.Test) -> String {
            let p = test.properties
            return #""\#(name)": {"properties": "#
                + #"{"disabled": \#(p.disabled)"#
                + #", "quarantined": \#(p.quarantined)"#
                + #", "attempt_to_fix": \#(p.attemptToFix)}}"#
        }
    }
}

private extension Endpoint {
    var testManagementTestsURL: URL {
        let endpoint = "/api/v2/test/libraries/test-management/tests"
        switch self {
        case let .other(testsBaseURL: url, logsBaseURL: _): return url.appendingPathComponent(endpoint)
        default: return mainApi(endpoint: endpoint)!
        }
    }
}
