/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import enum EventsExporter.Endpoint

public enum Endpoint {
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
    
    internal var exporterEndpoint: EventsExporter.Endpoint {
        switch self {
        case .us1: return .us1
        case .us3: return .us3
        case .us5: return .us5
        case .eu1: return .eu1
        case .ap1: return .ap1
        case .staging: return .staging
        case let .other(testsBaseURL: tURL, logsBaseURL: lURL): return .other(testsBaseURL: tURL, logsBaseURL: lURL)
        case let .custom(testsURL: tURL, logsURL: lURL): return .custom(testsURL: tURL, logsURL: lURL)
        }
    }
}

extension Endpoint: EnvironmentValue {
    init?(configValue: String) {
        switch configValue.lowercased() {
            case "us", "us1", "https://app.datadoghq.com", "app.datadoghq.com", "datadoghq.com":
                self = .us1
            case "us3", "https://us3.datadoghq.com", "us3.datadoghq.com":
                self = .us3
            case "us5", "https://us5.datadoghq.com", "us5.datadoghq.com":
                self = .us5
            case "eu", "eu1", "https://app.datadoghq.eu", "app.datadoghq.eu", "datadoghq.eu":
                self = .eu1
            case "ap", "ap1", "ap!", "https://ap1.datadoghq.com", "ap1.datadoghq.com":
                self = .ap1
//            case "gov", "us1_fed", "https://app.ddog-gov.com", "app.ddog-gov.com", "ddog-gov.com":
//                self = .us1_fed
            case "st", "staging", "https://dd.datad0g.com", "dd.datad0g.com", "datad0g.com":
                self = .staging
            default:
                return nil
        }
    }
}
