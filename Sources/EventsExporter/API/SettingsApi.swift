//
//  TestApi.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 28/10/2025.
//

import Foundation

public protocol SettingsApi: APIService {
    func tracerSettings(service: String, env: String,
                        repositoryURL: String, branch: String, sha: String,
                        tiaLevel: TIALevel,
                        configurations: [String: String],
                        customConfigurations: [String: String]) -> AsyncResult<TracerSettings, APICallError>
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
        
        init(response: SettingsApiService.SettingsResponse) {
            itrEnabled = response.itrEnabled
            codeCoverage = response.codeCoverage
            testsSkipping = response.testsSkipping
            requireGit = response.requireGit
        }
    }

    public struct TestManagement {
        public var enabled: Bool
        public var attemptToFixRetries: UInt

        init(response: SettingsApiService.SettingsResponse.TestManagement) {
            enabled = response.enabled
            attemptToFixRetries = response.attemptToFixRetries
        }
    }

    public struct EFD {
        public var enabled: Bool
        public var slowTestRetries: TimeTable
        public var faultySessionThreshold: Double
        
        init(response: SettingsApiService.SettingsResponse.EFD) {
            enabled = response.enabled
            faultySessionThreshold = response.faultySessionThreshold
            slowTestRetries = TimeTable(response: response.slowTestRetries)
        }
        
        public init() {
            enabled = false
            faultySessionThreshold = 0
            slowTestRetries = TimeTable(response: [:])
        }
    }
    
    public struct TimeTable {
        public var times: [(time: TimeInterval, count: UInt)]
        
        init(response: [String: UInt]) {
            times = response.compactMap { (key, val) in
                Self.time(key).map { (time: $0, count: val) }
            }
            times.sort { l, r in l.time < r.time }
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
    
    init(response: SettingsApiService.SettingsResponse) {
        flakyTestRetriesEnabled = response.flakyTestRetriesEnabled
        knownTestsEnabled = response.knownTestsEnabled
        itr = ITR(response: response)
        efd = EFD(response: response.earlyFlakeDetection)
        testManagement = TestManagement(response: response.testManagement)
    }
}

struct SettingsApiService: SettingsApi {
    typealias SettingsCall = APICall<APIDataNoMeta<SettingsRequest>, APIDataNoMeta<SettingsResponse>>
    
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
    
    public func tracerSettings(service: String, env: String,
                               repositoryURL: String, branch: String, sha: String,
                               tiaLevel: TIALevel,
                               configurations: [String: String],
                               customConfigurations: [String: String]) -> AsyncResult<TracerSettings, APICallError>
    {
        var configurations: [String: JSONGeneric] = configurations.mapValues { .string($0) }
        configurations["custom"] = .stringDict(customConfigurations)
        
        let request = SettingsRequest(service: service, env: env,
                                      repositoryUrl: repositoryURL,
                                      branch: branch,
                                      sha: sha,
                                      configurations: configurations,
                                      testLevel: tiaLevel)
        let log = self.log
        log.debug("Tracer settings request: \(request)")
        return httpClient.call(SettingsCall.self,
                        url: endpoint.settingsURL,
                        data: .init(attributes: request),
                        headers: headers + [.contentTypeHeader(contentType: .applicationJSON)],
                        coders: (encoder, decoder))
            .peek { log.debug("Tracer settings response: \($0)") }
            .mapValue { TracerSettings(response: $0.data.attributes) }
    }
    
    var endpointURLs: Set<URL> { [endpoint.settingsURL] }
}

extension SettingsApiService {
    struct SettingsRequest: APIAttributesUUID, Encodable {
        let service: String
        let env: String
        let repositoryUrl: String
        let branch: String
        let sha: String
        let configurations: [String: JSONGeneric]
        let testLevel: TIALevel
        
        static var apiType: String = "ci_app_test_service_libraries_settings"
    }
    
    struct SettingsResponse: APIAttributes, Decodable {
        struct EFD: Decodable {
            let enabled: Bool
            let slowTestRetries: [String: UInt]
            let faultySessionThreshold: Double
        }
        
        struct TestManagement: Decodable {
            let enabled: Bool
            let attemptToFixRetries: UInt
            
            init(enabled: Bool = false, attemptToFixRetries: UInt = 0) {
                self.enabled = enabled
                self.attemptToFixRetries = attemptToFixRetries
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
