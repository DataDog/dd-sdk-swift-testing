/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

enum CodeCoveragePriority: Int, EnvironmentValue, CustomDebugStringConvertible {
    case background = 0
    case utility = 1
    case userInitiated = 2
    case userInteractive = 3
    
    var qos: QualityOfService {
        switch self {
        case .background: return .background
        case .utility: return .utility
        case .userInitiated: return .userInitiated
        case .userInteractive: return .userInteractive
        }
    }
    
    init?(configValue: String) {
        guard let int = Int(configValue: configValue) else {
            return nil
        }
        guard let priority = Self(rawValue: int) else {
            return nil
        }
        self = priority
    }
    
    var debugDescription: String {
        switch self {
        case .background: return "background"
        case .utility: return "utility"
        case .userInitiated: return "userInitiated"
        case .userInteractive: return "userInteractive"
        }
    }
}
