/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

enum RuntimeInfo {
    case xcode(xcodeVersion: String, swiftVersion: String)
    case spm(swiftVersion: String)
    
    init(version xcode: String?, isXcode: Bool) {
        let env = ProcessInfo.processInfo.environment
        var swiftVer: String?
        if let xcode, !xcode.isEmpty {
            swiftVer = Self.xcodeVersionToSwift(xcode)
        }
        if swiftVer == nil {
            swiftVer = Self.spawnSwiftcVersion() ?? "<unknown>"
        }
        if isXcode {
            self = .xcode(xcodeVersion: Self.parseXcodeVersion(xcode ?? ""),
                          swiftVersion: swiftVer!)
        } else {
            self = .spm(swiftVersion: swiftVer!)
        }
    }
    
    var runtimeName: String {
        switch self {
        case .xcode: return "Xcode"
        case .spm: return "SPM"
        }
    }

    var runtimeVersion: String {
        switch self {
        case .xcode(let v, _): return v
        case .spm(let v): return v
        }
    }

    var swiftVersion: String {
        switch self {
        case .xcode(_, let v): return v
        case .spm(let v): return v
        }
    }

    // DTXcode format: 4-char string "XXYY" → major=XX, minor=Y, patch=Y
    // e.g. "2640" → 26.4, "2600" → 26.0
    private static func parseXcodeVersion(_ dtxcode: String) -> String {
        guard dtxcode.count == 4, let value = Int(dtxcode) else { return dtxcode }
        let major = value / 100
        let minor = (value % 100) / 10
        let patch = value % 10
        return patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }

    // Mapping for Xcode 26+, ordered descending so the first match wins.
    private static let xcodeSwiftMap: [(minDTXcode: Int, swiftVersion: String)] = [
        (2700, "6.4"),   // Xcode 27.0
        (2660, "6.3.3"), // Xcode 26.6
        (2650, "6.3.2"), // Xcode 26.5
        (2641, "6.3.1"), // Xcode 26.4.1
        (2640, "6.3"),   // Xcode 26.4
        (2630, "6.2.4"), // Xcode 26.3
        (2620, "6.2.3"), // Xcode 26.2
        (2610, "6.2.1"), // Xcode 26.1
        (2600, "6.2"),   // Xcode 26.0
    ]

    private static func xcodeVersionToSwift(_ dtxcode: String) -> String? {
        guard let value = Int(dtxcode) else { return nil }
        for (min, swift) in xcodeSwiftMap where value >= min {
            return swift
        }
        return nil
    }

    private static func spawnSwiftcVersion() -> String? {
        guard let output = try? Spawn.combined("swiftc --version") else { return nil }
        // Output: "...Apple Swift version 6.2 (swiftlang-6.2.0.9 ...)" or "Swift version 6.2 ..."
        let pattern = try? NSRegularExpression(pattern: #"Swift version (\d+\.\d+(?:\.\d+)?)"#)
        guard let match = pattern?.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else { return nil }
        return String(output[range])
    }
}
