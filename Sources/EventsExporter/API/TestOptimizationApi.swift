//
//  TestsApi.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 28/10/2025.
//

import Foundation

public protocol TestOpmimizationApi: APIService {
    var settings: SettingsApi { get }
    var knownTests: KnownTestsApi { get }
    var git: GitUploadApi { get }
    var tia: TestImpactAnalysisApi { get }
    var testManagement: TestManagementApi { get }
    var spans: SpansApi { get }
    var logs: LogsApi { get }
}

public struct TestOpmimizationApiService: TestOpmimizationApi {
    public var endpoint: Endpoint {
        get { settings.endpoint }
        set {
            settings.endpoint = newValue
            knownTests.endpoint = newValue
            git.endpoint = newValue
            tia.endpoint = newValue
            testManagement.endpoint = newValue
            spans.endpoint = newValue
            logs.endpoint = newValue
        }
    }
    public var headers: [HTTPHeader] {
        get { settings.headers }
        set {
            settings.headers = newValue
            knownTests.headers = newValue
            git.headers = newValue
            tia.headers = newValue
            testManagement.headers = newValue
            spans.headers = newValue
            logs.headers = newValue
        }
    }
    
    public var encoder: JSONEncoder {
        get { settings.encoder }
        set {
            settings.encoder = newValue
            knownTests.encoder = newValue
            git.encoder = newValue
            tia.encoder = newValue
            testManagement.encoder = newValue
            spans.encoder = newValue
            logs.encoder = newValue
        }
    }
    
    public var decoder: JSONDecoder {
        get { settings.decoder }
        set {
            settings.decoder = newValue
            knownTests.decoder = newValue
            git.decoder = newValue
            tia.decoder = newValue
            testManagement.decoder = newValue
            spans.decoder = newValue
            logs.decoder = newValue
        }
    }
    
    public var settings: SettingsApi
    public var knownTests: KnownTestsApi
    public var git: GitUploadApi
    public var tia: TestImpactAnalysisApi
    public var testManagement: TestManagementApi
    public var spans: SpansApi
    public var logs: LogsApi
    
    public init(config: APIServiceConfig, httpClient: HTTPClient, log: Logger) {
        settings = SettingsApiService(config: config, httpClient: httpClient, log: log)
        knownTests = KnownTestsApiService(config: config, httpClient: httpClient, log: log)
        git = GitUploadApiService(config: config, httpClient: httpClient, log: log)
        tia = TestImpactAnalysisApiService(config: config, httpClient: httpClient, log: log)
        testManagement = TestManagementApiService(config: config, httpClient: httpClient, log: log)
        spans = SpansApiService(config: config, httpClient: httpClient, log: log)
        logs = LogsApiService(config: config, httpClient: httpClient, log: log)
    }
    
    public var endpointURLs: Set<URL> {
        settings.endpointURLs
            .union(knownTests.endpointURLs)
            .union(git.endpointURLs)
            .union(tia.endpointURLs)
            .union(testManagement.endpointURLs)
            .union(spans.endpointURLs)
            .union(logs.endpointURLs)
    }
}
