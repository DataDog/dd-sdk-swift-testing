/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public struct TracerSettings {
    public let itr: ITR
    public let efd: EFD
    public let flakyTestRetriesEnabled: Bool
    public let knownTestsEnabled: Bool
    public let testManagement: TestManagement
    
    public var efdIsEnabled: Bool {
        knownTestsEnabled && efd.enabled
    }

    public struct ITR {
        public let itrEnabled: Bool
        public let codeCoverage: Bool
        public let testsSkipping: Bool
        public let requireGit: Bool
        
        init(attrs: SettingsService.SettingsResponse.Data.Attributes) {
            self.init(itrEnabled: attrs.itrEnabled, codeCoverage: attrs.codeCoverage,
                      testsSkipping: attrs.testsSkipping, requireGit: attrs.requireGit)
        }
        
        public init(itrEnabled: Bool = false, codeCoverage: Bool = false,
                    testsSkipping: Bool = false, requireGit: Bool = false)
        {
            self.itrEnabled = itrEnabled
            self.codeCoverage = codeCoverage
            self.testsSkipping = testsSkipping
            self.requireGit = requireGit
        }
    }

    public struct TestManagement {
        public let enabled: Bool
        public let attemptToFixRetries: UInt

        init(attrs: SettingsService.SettingsResponse.Data.Attributes.TestManagement) {
            enabled = attrs.enabled
            attemptToFixRetries = attrs.attemptToFixRetries
        }
    }

    public struct EFD {
        public let enabled: Bool
        public let slowTestRetries: TimeTable
        public let faultySessionThreshold: Double
        
        public struct TimeTable {
            public let times: [(time: TimeInterval, count: UInt)]
            
            public init(attrs: [String: UInt] = [:]) {
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
        
        init(attrs: SettingsService.SettingsResponse.Data.Attributes.EFD) {
            enabled = attrs.enabled
            faultySessionThreshold = attrs.faultySessionThreshold
            slowTestRetries = TimeTable(attrs: attrs.slowTestRetries)
        }
        
        public init(enabled: Bool = false, faultySessionThreshold: Double = 0, slowTestRetries: TimeTable = .init()) {
            self.enabled = enabled
            self.faultySessionThreshold = faultySessionThreshold
            self.slowTestRetries = slowTestRetries
        }
    }
    
    init(attrs: SettingsService.SettingsResponse.Data.Attributes) {
        self.init(itr: ITR(attrs: attrs),
                  efd: EFD(attrs: attrs.earlyFlakeDetection),
                  flakyTestRetriesEnabled: attrs.flakyTestRetriesEnabled,
                  knownTestsEnabled: attrs.knownTestsEnabled,
                  testManagement: TestManagement(attrs: attrs.testManagement))
    }
    
    public init(itr: ITR, efd: EFD, flakyTestRetriesEnabled: Bool, knownTestsEnabled: Bool, testManagement: TestManagement) {
        self.itr = itr
        self.efd = efd
        self.flakyTestRetriesEnabled = flakyTestRetriesEnabled
        self.knownTestsEnabled = knownTestsEnabled
        self.testManagement = testManagement
    }
}

internal class SettingsService {
    let exporterConfiguration: ExporterConfiguration
    let settingsUploader: DataUploader
    
    init(config: ExporterConfiguration) throws {
        self.exporterConfiguration = config
        
        let settingsRequestBuilder = SingleRequestBuilder(
            url: exporterConfiguration.endpoint.settingsURL,
            queryItems: [],
            headers: [
                .userAgentHeader(
                    appName: exporterConfiguration.applicationName,
                    appVersion: exporterConfiguration.version,
                    device: Device.current
                ),
                .contentTypeHeader(contentType: .applicationJSON),
                .apiKeyHeader(apiKey: config.apiKey),
                .traceIDHeader(traceID: config.exporterId),
                .parentSpanIDHeader(parentSpanID: config.exporterId),
                .samplingPriorityHeader()
            ]
        )
        
        settingsUploader = DataUploader(
            httpClient: HTTPClient(debug: config.debug.logNetworkRequests),
            requestBuilder: settingsRequestBuilder
        )
    }
    
    func settings(
        service: String, env: String, repositoryURL: String, branch: String, sha: String,
        testLevel: ITRTestLevel, configurations: [String: String], customConfigurations: [String: String]
    ) -> TracerSettings? {
        var configurations: [String: JSONGeneric] = configurations.mapValues { .string($0) }
        configurations["custom"] = .stringDict(customConfigurations)
        
        let settingsPayload = SettingsRequest(service: service, env: env, repositoryURL: repositoryURL,
                                              branch: branch, sha: sha, configurations: configurations,
                                              testLevel: testLevel)

        guard let jsonData = settingsPayload.jsonData,
              let response = settingsUploader.uploadWithResponse(data: jsonData)
        else {
            Log.debug("SettingsRequest payload: \(settingsPayload.jsonString)")
            Log.debug("SettingsRequest no response")
            return nil
        }

        guard let settings = try? JSONDecoder().decode(SettingsResponse.self, from: response) else {
            Log.debug("SettingsRequest payload: \(settingsPayload.jsonString)")
            Log.debug("SettingsRequest invalid response: \(String(decoding: response, as: UTF8.self))")
            return nil
        }
        Log.debug("SettingsRequest response: \(String(decoding: response, as: UTF8.self))")

        return TracerSettings(attrs: settings.data.attributes)
    }
}

extension SettingsService {
    struct SettingsRequest: Codable, JSONable {
        let data: Data
        
        struct Data: Codable {
            var id = "1"
            var type = "ci_app_test_service_libraries_settings"
            let attributes: Attributes
            
            struct Attributes: Codable {
                let service: String
                let env: String
                let repositoryURL: String
                let branch: String
                let sha: String
                let configurations: [String: JSONGeneric]
                let testLevel: ITRTestLevel
                
                enum CodingKeys: String, CodingKey {
                    case service
                    case env
                    case repositoryURL = "repository_url"
                    case branch
                    case sha
                    case configurations
                    case testLevel = "test_level"
                }
            }
        }
        
        init(
            service: String, env: String, repositoryURL: String, branch: String,
            sha: String, configurations: [String: JSONGeneric], testLevel: ITRTestLevel
        ) {
            self.data = Data(
                attributes: Data.Attributes(
                    service: service, env: env, repositoryURL: repositoryURL, branch: branch, sha: sha,
                    configurations: configurations, testLevel: testLevel
                )
            )
        }
    }
    
    struct SettingsResponse: Codable, JSONable {
        let data: Data

        struct Data: Codable {
            let attributes: Attributes
            var id = "1"
            var type = "ci_app_tracers_test_service_settings"

            struct Attributes: Codable {
                let itrEnabled: Bool
                let codeCoverage: Bool
                let testsSkipping: Bool
                let knownTestsEnabled: Bool
                let requireGit: Bool
                let flakyTestRetriesEnabled: Bool
                let earlyFlakeDetection: EFD
                let testManagement: TestManagement

                enum CodingKeys: String, CodingKey {
                    case itrEnabled = "itr_enabled"
                    case codeCoverage = "code_coverage"
                    case testsSkipping = "tests_skipping"
                    case knownTestsEnabled = "known_tests_enabled"
                    case requireGit = "require_git"
                    case flakyTestRetriesEnabled = "flaky_test_retries_enabled"
                    case earlyFlakeDetection = "early_flake_detection"
                    case testManagement = "test_management"
                }
                
                struct EFD: Codable {
                    let enabled: Bool
                    let slowTestRetries: [String: UInt]
                    let faultySessionThreshold: Double
                    
                    enum CodingKeys: String, CodingKey {
                        case enabled
                        case slowTestRetries = "slow_test_retries"
                        case faultySessionThreshold = "faulty_session_threshold"
                    }
                }

                struct TestManagement: Codable {
                    let enabled: Bool
                    let attemptToFixRetries: UInt
                    
                    init(enabled: Bool = false, attemptToFixRetries: UInt = 0) {
                        self.enabled = enabled
                        self.attemptToFixRetries = attemptToFixRetries
                    }

                    enum CodingKeys: String, CodingKey {
                        case enabled
                        case attemptToFixRetries = "attempt_to_fix_retries"
                    }
                }
            }
        }
    }
}

