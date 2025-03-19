/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

enum SDKCapability: Equatable, Hashable {
    case testImpactAnalysis
    case earlyFlakeDetection
    case autoTestRetries
    case impactedTest
    case failFastTestOrder
    case testManagementQuarantine
    case testManagementDisable
    case testManagementAttemptToFix
    
    var metadata: (key: String, value: String) {
        switch self {
        case .testImpactAnalysis: return (DDLibraryCapabilitiesTags.testImpactAnalysis, "1")
        case .earlyFlakeDetection: return (DDLibraryCapabilitiesTags.earlyFlakeDetection, "1")
        case .autoTestRetries: return (DDLibraryCapabilitiesTags.autoTestRetries, "1")
        case .impactedTest: return (DDLibraryCapabilitiesTags.impactedTests, "1")
        case .failFastTestOrder: return (DDLibraryCapabilitiesTags.failFastTestOrder, "1")
        case .testManagementQuarantine: return (DDLibraryCapabilitiesTags.testManagementQuarantine, "1")
        case .testManagementDisable: return (DDLibraryCapabilitiesTags.testManagementDisable, "1")
        case .testManagementAttemptToFix: return (DDLibraryCapabilitiesTags.testManagementAttemptToFix, "2")
        }
    }
    
    static var library: Set<Self> {
        [.testImpactAnalysis, .earlyFlakeDetection, .autoTestRetries]
    }
    
    static var all: Set<Self> {
        [.testImpactAnalysis, .earlyFlakeDetection,
         .autoTestRetries, .impactedTest, .failFastTestOrder,
         .testManagementQuarantine, .testManagementDisable,
         .testManagementAttemptToFix]
    }
}

typealias SDKCapabilities = Set<SDKCapability>

extension SDKCapabilities {
    static var libraryCapabilities: Self { SDKCapability.library }
    static var allCapabilities: Self { SDKCapability.all }
}
