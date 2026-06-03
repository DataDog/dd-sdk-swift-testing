/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public protocol SettingsApi: APIService {
    func tracerSettings(service: String, env: String,
                        repositoryURL: String, branch: String, sha: String,
                        testLevel: ITRTestLevel,
                        configurations: [String: String],
                        customConfigurations: [String: String],
                        observer: RequestObserver?) async throws(APICallError) -> TracerSettings
}

public extension SettingsApi {
    /// Convenience without a telemetry observer.
    @inlinable
    func tracerSettings(service: String, env: String,
                        repositoryURL: String, branch: String, sha: String,
                        testLevel: ITRTestLevel,
                        configurations: [String: String],
                        customConfigurations: [String: String]) async throws(APICallError) -> TracerSettings
    {
        try await tracerSettings(service: service, env: env, repositoryURL: repositoryURL,
                                 branch: branch, sha: sha, testLevel: testLevel,
                                 configurations: configurations,
                                 customConfigurations: customConfigurations, observer: nil)
    }
}

public struct TracerSettings {
    public var itr: ITR
    public var efd: EFD
    public var flakyTestRetriesEnabled: Bool
    public var knownTestsEnabled: Bool
    public var testManagement: TestManagement

    public var efdIsEnabled: Bool {
        knownTestsEnabled && efd.enabled
    }

    public struct ITR {
        public var itrEnabled: Bool
        public var codeCoverage: Bool
        public var testsSkipping: Bool
        public var requireGit: Bool

        public init(itrEnabled: Bool = false, codeCoverage: Bool = false,
                    testsSkipping: Bool = false, requireGit: Bool = false)
        {
            self.itrEnabled = itrEnabled
            self.codeCoverage = codeCoverage
            self.testsSkipping = testsSkipping
            self.requireGit = requireGit
        }

        init(response: SettingsApiService.SettingsResponse) {
            self.init(itrEnabled: response.itrEnabled,
                      codeCoverage: response.codeCoverage,
                      testsSkipping: response.testsSkipping,
                      requireGit: response.requireGit)
        }
    }

    public struct TestManagement {
        public var enabled: Bool
        public var attemptToFixRetries: UInt

        public init(enabled: Bool = false, attemptToFixRetries: UInt = 0) {
            self.enabled = enabled
            self.attemptToFixRetries = attemptToFixRetries
        }

        init(response: SettingsApiService.SettingsResponse.TestManagement) {
            self.init(enabled: response.enabled, attemptToFixRetries: response.attemptToFixRetries)
        }
    }

    public struct EFD {
        public var enabled: Bool
        public var slowTestRetries: TimeTable
        public var faultySessionThreshold: Double

        public init(enabled: Bool = false,
                    faultySessionThreshold: Double = 0,
                    slowTestRetries: TimeTable = TimeTable())
        {
            self.enabled = enabled
            self.faultySessionThreshold = faultySessionThreshold
            self.slowTestRetries = slowTestRetries
        }

        init(response: SettingsApiService.SettingsResponse.EFD) {
            self.init(enabled: response.enabled,
                      faultySessionThreshold: response.faultySessionThreshold,
                      slowTestRetries: TimeTable(attrs: response.slowTestRetries))
        }

        public struct TimeTable {
            public var times: [(time: TimeInterval, count: UInt)]

            public init(times: [(time: TimeInterval, count: UInt)] = []) {
                self.times = times.sorted { l, r in l.time < r.time }
            }

            public init(attrs: [String: UInt]) {
                var times = attrs.compactMap { (key, val) in
                    Self.time(key).map { (time: $0, count: val) }
                }
                times.sort { l, r in l.time < r.time }
                self.times = times
            }

            public func repeats(for time: TimeInterval) -> UInt {
                let rounded = time.rounded()
                guard let index = times.firstIndex(where: { $0.time > rounded }) else {
                    return 0
                }
                guard index > 0 else { return times[index].count }
                return times[index-1].count
            }

            private static func time(_ val: String) -> TimeInterval? {
                guard val.count >= 2 else { return nil }
                let lastElement = val.index(before: val.endIndex)
                guard let interval = TimeInterval(val.prefix(upTo: lastElement)) else { return nil }
                switch val[lastElement] {
                case "s", "S": return interval
                case "m", "M": return interval * 60.0
                case "h", "H": return interval * 3600.0
                default: return nil
                }
            }
        }
    }

    public init(itr: ITR, efd: EFD,
                flakyTestRetriesEnabled: Bool, knownTestsEnabled: Bool,
                testManagement: TestManagement)
    {
        self.itr = itr
        self.efd = efd
        self.flakyTestRetriesEnabled = flakyTestRetriesEnabled
        self.knownTestsEnabled = knownTestsEnabled
        self.testManagement = testManagement
    }

    init(response: SettingsApiService.SettingsResponse) {
        self.init(itr: ITR(response: response),
                  efd: EFD(response: response.earlyFlakeDetection),
                  flakyTestRetriesEnabled: response.flakyTestRetriesEnabled,
                  knownTestsEnabled: response.knownTestsEnabled,
                  testManagement: TestManagement(response: response.testManagement))
    }
}

struct SettingsApiService: SettingsApi, APIServiceConstructible {
    typealias SettingsCall = APICall<APIDataNoMeta<SettingsRequest>, APIDataNoMeta<SettingsResponse>>

    var endpoint: Endpoint
    var headers: [HTTPHeader]
    var encoder: JSONEncoder
    var decoder: JSONDecoder
    let httpClient: any HTTPClientType
    let log: Logger

    init(config: APIServiceConfig, httpClient: any HTTPClientType, log: Logger) {
        self.endpoint = config.endpoint
        self.httpClient = httpClient
        self.log = log
        self.headers = config.defaultHeaders
        self.encoder = config.encoder
        self.decoder = config.decoder
    }

    func tracerSettings(service: String, env: String,
                        repositoryURL: String, branch: String, sha: String,
                        testLevel: ITRTestLevel,
                        configurations: [String: String],
                        customConfigurations: [String: String],
                        observer: RequestObserver?) async throws(APICallError) -> TracerSettings
    {
        var configurations: [String: JSONGeneric] = configurations.mapValues { .string($0) }
        configurations["custom"] = JSONGeneric(customConfigurations)

        let request = SettingsRequest(service: service, env: env,
                                      repositoryUrl: repositoryURL,
                                      branch: branch,
                                      sha: sha,
                                      configurations: configurations,
                                      testLevel: testLevel)
        let log = self.log
        log.debug("Tracer settings request: \(request)")
        let response = try await httpClient.call(SettingsCall.self,
                                                 url: endpoint.settingsURL,
                                                 data: .init(attributes: request),
                                                 headers: headers + [.contentTypeHeader(contentType: .applicationJSON)],
                                                 coders: (encoder, decoder),
                                                 observer: observer)
        log.debug("Tracer settings response: \(response.data.attributes)")
        return TracerSettings(response: response.data.attributes)
    }

    var endpointURLs: Set<URL> { [endpoint.settingsURL] }
}

extension SettingsApiService {
    struct SettingsRequest: APIAttributesUUID, Encodable, CustomDebugStringConvertible {
        let service: String
        let env: String
        let repositoryUrl: String
        let branch: String
        let sha: String
        let configurations: [String: JSONGeneric]
        let testLevel: ITRTestLevel

        static var apiType: String = "ci_app_test_service_libraries_settings"

        var debugDescription: String {
            let configs = JSONGeneric.object(configurations).debugDescription
            return #"{"service": "\#(service)""#
                + #", "env": "\#(env)""#
                + #", "repository_url": "\#(repositoryUrl)""#
                + #", "branch": "\#(branch)""#
                + #", "sha": "\#(sha)""#
                + #", "configurations": \#(configs)"#
                + #", "test_level": "\#(testLevel.rawValue)"}"#
        }
    }

    struct SettingsResponse: APIResponseAttributesHasType, APIResponseAttributesHasId,
                             Decodable, CustomDebugStringConvertible
    {
        struct EFD: Decodable, CustomDebugStringConvertible {
            let enabled: Bool
            let slowTestRetries: [String: UInt]
            let faultySessionThreshold: Double

            var debugDescription: String {
                let retries = slowTestRetries.map { #""\#($0)": \#($1)"# }.joined(separator: ", ")
                return #"{"enabled": \#(enabled)"#
                    + #", "slow_test_retries": {\#(retries)}"#
                    + #", "faulty_session_threshold": \#(faultySessionThreshold)}"#
            }
        }

        struct TestManagement: Decodable, CustomDebugStringConvertible {
            let enabled: Bool
            let attemptToFixRetries: UInt

            init(enabled: Bool = false, attemptToFixRetries: UInt = 0) {
                self.enabled = enabled
                self.attemptToFixRetries = attemptToFixRetries
            }

            var debugDescription: String {
                #"{"enabled": \#(enabled), "attempt_to_fix_retries": \#(attemptToFixRetries)}"#
            }
        }

        let itrEnabled: Bool
        let codeCoverage: Bool
        let testsSkipping: Bool
        let knownTestsEnabled: Bool
        let requireGit: Bool
        let flakyTestRetriesEnabled: Bool
        let earlyFlakeDetection: EFD
        let testManagement: TestManagement

        static var apiType: String = "ci_app_tracers_test_service_settings"

        var debugDescription: String {
            #"{"itr_enabled": \#(itrEnabled)"#
                + #", "code_coverage": \#(codeCoverage)"#
                + #", "tests_skipping": \#(testsSkipping)"#
                + #", "known_tests_enabled": \#(knownTestsEnabled)"#
                + #", "require_git": \#(requireGit)"#
                + #", "flaky_test_retries_enabled": \#(flakyTestRetriesEnabled)"#
                + #", "early_flake_detection": \#(earlyFlakeDetection)"#
                + #", "test_management": \#(testManagement)}"#
        }
    }
}

private extension Endpoint {
    var settingsURL: URL {
        let endpoint = "/api/v2/libraries/tests/services/setting"
        switch self {
        case let .other(testsBaseURL: url, logsBaseURL: _): return url.appendingPathComponent(endpoint)
        default: return mainApi(endpoint: endpoint)!
        }
    }
}
