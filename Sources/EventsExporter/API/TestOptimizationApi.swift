/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public protocol TestOptimizationApi: APIService {
    var settings: SettingsApi { get }
    var knownTests: KnownTestsApi { get }
    var git: GitUploadApi { get }
    var tia: TestImpactAnalysisApi { get }
    var testManagement: TestManagementApi { get }
    var spans: SpansApi { get }
    var logs: LogsApi { get }
    var telemetry: TelemetryApi { get }
}

public struct TestOptimizationApiService: TestOptimizationApi {
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
            telemetry.endpoint = newValue
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
            telemetry.headers = newValue
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
            telemetry.encoder = newValue
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
            telemetry.decoder = newValue
        }
    }

    public private(set) var settings: SettingsApi
    public private(set) var knownTests: KnownTestsApi
    public private(set) var git: GitUploadApi
    public private(set) var tia: TestImpactAnalysisApi
    public private(set) var testManagement: TestManagementApi
    public private(set) var spans: SpansApi
    public private(set) var logs: LogsApi
    public private(set) var telemetry: TelemetryApi

    internal init(config: APIServiceConfig, httpClient: HTTPClient, log: Logger) {
        settings = SettingsApiService(config: config, httpClient: httpClient, log: log)
        knownTests = KnownTestsApiService(config: config, httpClient: httpClient, log: log)
        git = GitUploadApiService(config: config, httpClient: httpClient, log: log)
        tia = TestImpactAnalysisApiService(config: config, httpClient: httpClient, log: log)
        testManagement = TestManagementApiService(config: config, httpClient: httpClient, log: log)
        spans = SpansApiService(config: config, httpClient: httpClient, log: log)
        logs = LogsApiService(config: config, httpClient: httpClient, log: log)
        telemetry = TelemetryApiService(config: config, httpClient: httpClient, log: log)
    }

    /// Build the full set of test-optimization API services that share one
    /// `HTTPClient` and one set of identity headers. Callers (the SDK) own the
    /// resulting value and pass it to `EventsExporter`.
    public init(serviceName: String, environment: String,
                applicationName: String, version: String,
                hostname: String?, apiKey: String,
                endpoint: Endpoint, clientId: String,
                payloadCompression: Bool,
                logger: Logger,
                debugNetworkRequests: Bool = false)
    {
        let config = APIServiceConfig(serviceName: serviceName, environment: environment,
                                      applicationName: applicationName, version: version,
                                      device: .current, hostname: hostname, apiKey: apiKey,
                                      endpoint: endpoint, clientId: clientId,
                                      payloadCompression: payloadCompression)
        self.init(config: config,
                  httpClient: HTTPClient(debug: debugNetworkRequests),
                  log: logger)
    }

    public var endpointURLs: Set<URL> {
        settings.endpointURLs
            .union(knownTests.endpointURLs)
            .union(git.endpointURLs)
            .union(tia.endpointURLs)
            .union(testManagement.endpointURLs)
            .union(spans.endpointURLs)
            .union(logs.endpointURLs)
            .union(telemetry.endpointURLs)
    }
}
