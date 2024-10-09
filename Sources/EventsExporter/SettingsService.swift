/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public struct TracerSettings {
    public var itr: ITR
    public var efd: EFD
    public var flakyTestRetriesEnabled: Bool

    public struct ITR {
        public var itrEnabled: Bool
        public var codeCoverage: Bool
        public var testsSkipping: Bool
        public var requireGit: Bool
        
        init(attrs: SettingsService.SettingsResponse.Data.Attributes) {
            itrEnabled = attrs.itrEnabled
            codeCoverage = attrs.codeCoverage
            testsSkipping = attrs.testsSkipping
            requireGit = attrs.requireGit
        }
    }
    
    public struct EFD {
        public var enabled: Bool
        public var slowTestRetries: TimeTable
        public var faultySessionThreshold: Double
        
        public struct TimeTable {
            public var times: [(time: TimeInterval, count: UInt)]
            
            init(attrs: [String: UInt]) {
                times = attrs.compactMap { (key, val) in
                    Self.time(key).map { (time: $0, count: val) }
                }
                times.sort { l, r in l.time < r.time }
            }
            
            public func repeats(for time: TimeInterval) -> UInt {
                let rounded = time.rounded()
                guard let index = times.firstIndex(where: { $0.time > rounded }) else {
                    return times.last?.count ?? 0
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
        
        public init() {
            enabled = false
            faultySessionThreshold = 0
            slowTestRetries = TimeTable(attrs: [:])
        }
    }
    
    init(attrs: SettingsService.SettingsResponse.Data.Attributes) {
        flakyTestRetriesEnabled = attrs.flakyTestRetriesEnabled
        itr = ITR(attrs: attrs)
        efd = EFD(attrs: attrs.earlyFlakeDetection)
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
                let requireGit: Bool
                let flakyTestRetriesEnabled: Bool
                let earlyFlakeDetection: EFD
                
                enum CodingKeys: String, CodingKey {
                    case itrEnabled = "itr_enabled"
                    case codeCoverage = "code_coverage"
                    case testsSkipping = "tests_skipping"
                    case requireGit = "require_git"
                    case flakyTestRetriesEnabled = "flaky_test_retries_enabled"
                    case earlyFlakeDetection = "early_flake_detection"
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
            }
        }
    }
}

