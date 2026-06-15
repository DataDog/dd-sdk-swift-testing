/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
#if canImport(WatchKit)
    import WatchKit
#endif
#if canImport(UIKit)
    import UIKit
#elseif canImport(Cocoa)
    import Cocoa
    import SystemConfiguration
#endif
internal import CodeCoverage
internal import EventsExporter

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
        #elseif os(visionOS)
            platform = "visionOS"
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
        #elseif arch(arm64_32)
            return "arm64_32"
        #else
            return "unknown"
        #endif
    }

    static func getDeviceName() -> String {
        #if os(watchOS)
            return WKInterfaceDevice.current().name
        #elseif os(iOS) || os(tvOS) || os(visionOS)
            return UIDevice.current.name
        #else
            return (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
        #endif
    }

    static func getDeviceModel() -> String {
        #if os(watchOS)
            #if targetEnvironment(simulator)
                return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? (WKInterfaceDevice.current().model + " simulator")
            #else
                return WKInterfaceDevice.current().model
            #endif
        #elseif os(iOS) || os(tvOS) || os(visionOS)
            #if targetEnvironment(simulator)
                return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? (UIDevice.current.model + " simulator")
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

    static func getPlatformVersion() -> String {
        return ProcessInfo.processInfo.operatingSystemVersionString
    }

    static func getXcodeVersion() -> String {
        guard let xcTestClass = NSClassFromString("XCTest") else { return "" }
        let bundle = Bundle(for: xcTestClass)
        let version = bundle.infoDictionary?["DTXcode"] as? String ?? ""
        return version
    }

    static func getXCTestVersion() -> String? {
        guard let xcTestClass = NSClassFromString("XCTest") else { return nil }
        return Bundle(for: xcTestClass).infoDictionary?["CFBundleShortVersionString"] as? String
    }
    
    static func getSwiftTestingVersion() -> String? {
        Bundle.allFrameworks
            .first { $0.bundleIdentifier == "com.apple.dt.swift-testing" }
            .flatMap { $0.infoDictionary?["CFBundleVersion"] as? String }
    }

    static func getRuntimeInfo() -> RuntimeInfo {
        let isXcode = ProcessInfo.processInfo.environment["XCODE_SCHEME_NAME"] != nil
        var xcodeVersion: String? = getXcodeVersion()
        if xcodeVersion?.isEmpty ?? true { xcodeVersion = nil }
        return RuntimeInfo(version: xcodeVersion, isXcode: isXcode)
    }
    
    static func getCpuCount() -> Int {
        ProcessInfo.processInfo.processorCount
    }

    static func getAppearance() -> String {
        #if os(watchOS)
            return "unspecified"
        #elseif os(iOS) || os(tvOS) || os(visionOS)
            let appearance: String
            switch UITraitCollection.current.userInterfaceStyle {
                case .unspecified:
                    appearance = "unspecified"
                case .light:
                    appearance = "light"
                case .dark:
                    appearance = "dark"
                @unknown default:
                    appearance = "unknown"
            }
            return appearance
        #else
            return NSApp?.effectiveAppearance.name.rawValue ?? "light"
        #endif
    }


    #if os(iOS)
        static func getOrientation() -> String {
            let scene = UIApplication.shared.connectedScenes
                        .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            let orientation: UIInterfaceOrientation = scene?.interfaceOrientation ?? .portrait
            switch orientation {
                case .unknown:
                    return "unknown"
                case .portrait:
                    return "portrait"
                case .portraitUpsideDown:
                    return "portraitUpsideDown"
                case .landscapeLeft:
                    return "landscapeRight"
                case .landscapeRight:
                    return "landscapeLeft"
                @unknown default:
                    return "portrait"
            }
        }
    #endif

    static func getLocalization() -> String {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            return Locale.current.languageCode ?? "none"
        #else
            return NSLocale.current.languageCode ?? "none"
        #endif
    }
    
    static func getDeviceInfo() -> Device {
        Device(name: getDeviceName(),
               model: getDeviceModel(),
               osName: getRunningPlatform(),
               osVersion: getPlatformVersion(),
               osArchitecture: getPlatformArchitecture())
    }
    
    static func getKernelInfo() -> KernelInfo {
        var info = utsname()
        guard uname(&info) == 0 else {
            return KernelInfo(sysname: "", release: "", version: "", machine: "")
        }
        func str<T>(_ ptr: UnsafePointer<T>) -> String {
            ptr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
                String(cString: $0)
            }
        }
        return KernelInfo(
            sysname: str(&info.sysname),
            release: str(&info.release),
            version: str(&info.version),
            machine: str(&info.machine)
        )
    }
    
    static var xcodeVersion: XcodeVersion {
        .xcode26
    }
}
