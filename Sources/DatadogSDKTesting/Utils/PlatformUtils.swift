/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
#if os(iOS) || os(tvOS) || os(watchOS)
    import UIKit
#else
    import SystemConfiguration
#endif
struct PlatformUtils {
    static func getRunningPlatform() -> String {
        var platform: String
        #if os(iOS)
            #if targetEnvironment(macCatalyst)
                platform = "macCatalyst"
            #else
                platform = "iOS"
            #endif
        #elseif os(tvOS)
            platform = "tvOS"
        #elseif os(watchOS)
            platform = "watchOS"
        #else
            platform = "macOS"
        #endif

        #if targetEnvironment(simulator)
            platform += " simulator"
        #endif
        return platform
    }

    static func getPlatformArchitecture() -> String {
        #if arch(i386)
            return "i386"
        #elseif arch(x86_64)
            return "x86_64"
        #elseif arch(arm)
            return "arm"
        #elseif arch(arm64)
            return "arm64"
        #endif
    }

    static func getDeviceName() -> String {
        #if os(iOS) || os(tvOS) || os(watchOS)
            return UIDevice.current.name
        #else
            return (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
        #endif
    }

    static func getDeviceModel() -> String {
        #if os(iOS) || os(tvOS) || os(watchOS)
            #if targetEnvironment(simulator)
                return UIDevice.current.model + " simulator"
            #else
                return UIDevice.current.modelName
            #endif
        #else
            var size = 0
            sysctlbyname("hw.machine", nil, &size, nil, 0)
            var machine = [CChar](repeating: 0, count: size)
            sysctlbyname("hw.machine", &machine, &size, nil, 0)
            return String(cString: machine)
        #endif
    }

    static func getDeviceVersion() -> String {
        return ProcessInfo.processInfo.operatingSystemVersionString
    }

    static func getXcodeVersion() -> String {
        guard let xcTestClass = NSClassFromString("XCTest") else { return "" }
        let bundle = Bundle(for: xcTestClass)
        let version = bundle.infoDictionary?["DTXcode"] as? String ?? ""
        return version
    }
}
