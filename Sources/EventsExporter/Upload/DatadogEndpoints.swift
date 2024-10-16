/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public enum Endpoint: CustomDebugStringConvertible {
    /// US based servers.
    /// Sends data to [app.datadoghq.com](https://app.datadoghq.com/).
    case us1
    /// US3 based servers.
    /// Sends data to [us3.datadoghq.com](https://us3.datadoghq.com/).
    case us3
    /// US based servers.
    /// Sends data to [app.datadoghq.com](https://us5.datadoghq.com/).
    case us5
    /// Europe based servers.
    /// Sends data to [app.datadoghq.eu](https://app.datadoghq.eu/).
    case eu1
    /// Japan based servers.
    /// Sends data to [app.datadoghq.eu](https://ap1.datadoghq.com/).
    case ap1
    /// Gov servers.
    /// Sends data to [app.ddog-gov.com](https://app.ddog-gov.com/).
    //   case us1_fed
    /// Staging servers.
    /// Sends data to [app.datadoghq.eu](https://dd.datad0g.com/).
    case staging
    // Datadog path scheme compatible server
    case other(testsBaseURL: URL, logsBaseURL: URL)
    /// Fully-custom user-defined server.
    case custom(testsURL: URL, logsURL: URL)
    
    internal var logsURL: URL {
        let endpoint = "/api/v2/logs"
        switch self {
        case .us1: return URL(string: "https://logs.browser-intake-datadoghq.com" + endpoint)!
        case .us3: return URL(string: "https://logs.browser-intake-us3-datadoghq.com" + endpoint)!
        case .us5: return URL(string: "https://logs.browser-intake-us5-datadoghq.com" + endpoint)!
        case .eu1: return URL(string: "https://mobile-http-intake.logs.datadoghq.eu" + endpoint)!
        case .ap1: return URL(string: "https://logs.browser-intake-ap1-datadoghq.com" + endpoint)!
        case .staging: return URL(string: "https://logs.browser-intake-datad0g.com" + endpoint)!
        case let .other(testsBaseURL: _, logsBaseURL: url): return url.appendingPathComponent(endpoint)
        case let .custom(_, logsURL: logsUrl): return logsUrl
        }
    }
    
    internal var spansURL: URL {
        let endpoint = "/api/v2/citestcycle"
        switch self {
        case .us1: return URL(string: "https://citestcycle-intake.datadoghq.com" + endpoint)!
        case .us3: return URL(string: "https://citestcycle-intake.us3.datadoghq.com" + endpoint)!
        case .us5: return URL(string: "https://citestcycle-intake.us5.datadoghq.com" + endpoint)!
        case .eu1: return URL(string: "https://citestcycle-intake.datadoghq.eu" + endpoint)!
        case .ap1: return URL(string: "https://citestcycle-intake.ap1.datadoghq.com" + endpoint)!
        case .staging: return URL(string: "https://citestcycle-intake.datad0g.com" + endpoint)!
        case let .other(testsBaseURL: url, logsBaseURL: _): return url.appendingPathComponent(endpoint)
        case let .custom(testsURL: testsURL, _): return testsURL
        }
    }
    
    internal var coverageURL: URL {
        let endpoint = "/api/v2/citestcov"
        switch self {
        case .us1: return URL(string: "https://event-platform-intake.datadoghq.com" + endpoint)!
        case .us3: return URL(string: "https://event-platform-intake.us3.datadoghq.com" + endpoint)!
        case .us5: return URL(string: "https://event-platform-intake.us5.datadoghq.com" + endpoint)!
        case .eu1: return URL(string: "https://event-platform-intake.datadoghq.eu" + endpoint)!
        case .ap1: return URL(string: "https://event-platform-intake.ap1.datadoghq.com" + endpoint)!
        case .staging: return URL(string: "https://event-platform-intake.datad0g.com" + endpoint)!
        case let .other(testsBaseURL: url, logsBaseURL: _): return url.appendingPathComponent(endpoint)
        case let .custom(testsURL: testsURL, _): return testsURL
        }
    }
    
    internal var searchCommitsURL: URL {
        let endpoint = "/api/v2/git/repository/search_commits"
        switch self {
        case let .other(testsBaseURL: url, logsBaseURL: _): return url.appendingPathComponent(endpoint)
        case let .custom(testsURL: testsURL, _): return testsURL
        default: return mainApi(endpoint: endpoint)!
        }
    }
    
    internal var skippableTestsURL: URL {
        let endpoint = "/api/v2/ci/tests/skippable"
        switch self {
        case let .other(testsBaseURL: url, logsBaseURL: _): return url.appendingPathComponent(endpoint)
        case let .custom(testsURL: testsURL, _): return testsURL
        default: return mainApi(endpoint: endpoint)!
        }
    }
    
    internal var packfileURL: URL {
        let endpoint = "/api/v2/git/repository/packfile"
        switch self {
        case let .other(testsBaseURL: url, logsBaseURL: _): return url.appendingPathComponent(endpoint)
        case let .custom(testsURL: testsURL, _): return testsURL
        default: return mainApi(endpoint: endpoint)!
        }
    }
    
    internal var settingsURL: URL {
        let endpoint = "/api/v2/libraries/tests/services/setting"
        switch self {
        case let .other(testsBaseURL: url, logsBaseURL: _): return url.appendingPathComponent(endpoint)
        case let .custom(testsURL: testsURL, _): return testsURL
        default: return mainApi(endpoint: endpoint)!
        }
    }
    
    internal var knownTestsURL: URL {
        let endpoint = "/api/v2/ci/libraries/tests"
        switch self {
        case let .other(testsBaseURL: url, logsBaseURL: _): return url.appendingPathComponent(endpoint)
        case let .custom(testsURL: testsURL, _): return testsURL
        default: return mainApi(endpoint: endpoint)!
        }
    }
    
    public var debugDescription: String {
        switch self {
        case .us1: return "us1"
        case .us3: return "us3"
        case .us5: return "us5"
        case .eu1: return "eu1"
        case .ap1: return "ap1"
        case .staging: return "staging"
        case let .other(testsBaseURL: tUrl, logsBaseURL: lUrl): return "other(tests: \(tUrl), logs: \(lUrl))"
        case let .custom(testsURL: tUrl, logsURL: lUrl): return "custom(tests: \(tUrl), logs: \(lUrl))"
        }
    }
    
    private func mainApi(endpoint: String) -> URL? {
        switch self {
        case .us1: return URL(string: "https://api.datadoghq.com" + endpoint)
        case .us3: return URL(string: "https://api.us3.datadoghq.com" + endpoint)
        case .us5: return URL(string: "https://api.us5.datadoghq.com" + endpoint)
        case .eu1: return URL(string: "https://api.datadoghq.eu" + endpoint)
        case .ap1: return URL(string: "https://api.ap1.datadoghq.com" + endpoint)
        case .staging: return URL(string: "https://api.datad0g.com" + endpoint)
        default: return nil
        }
    }
}
