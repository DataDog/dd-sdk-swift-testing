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
    
    public var debugDescription: String {
        switch self {
        case .us1: return "us1"
        case .us3: return "us3"
        case .us5: return "us5"
        case .eu1: return "eu1"
        case .ap1: return "ap1"
        case .staging: return "staging"
        case let .other(testsBaseURL: tUrl, logsBaseURL: lUrl): return "other(tests: \(tUrl), logs: \(lUrl))"
        }
    }
    
    internal var site: String? {
        switch self {
        case .us1: return "datadoghq.com"
        case .us3: return "us3.datadoghq.com"
        case .us5: return "us5.datadoghq.com"
        case .eu1: return "datadoghq.eu"
        case .ap1: return "ap1.datadoghq.com"
        case .staging: return "datad0g.com"
        case let .other(testsBaseURL: tUrl, logsBaseURL: lUrl): return nil
        }
    }
    
    internal func mainApi(endpoint: String) -> URL? {
        site.flatMap { URL(string: "https://api.\($0)\(endpoint)") }
    }
}
