/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
#if os(iOS) || os(tvOS) || os(watchOS)
    import UIKit
#else
    import Cocoa
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

    static func getDeviceVersion() -> String {
        return ProcessInfo.processInfo.operatingSystemVersionString
    }

    static func getXcodeVersion() -> String {
        guard let xcTestClass = NSClassFromString("XCTest") else { return "" }
        let bundle = Bundle(for: xcTestClass)
        let version = bundle.infoDictionary?["DTXcode"] as? String ?? ""
        return version
    }

    static func getRuntimeInfo() -> (String, String) {
        if NSClassFromString("XCTest") != nil {
            return ("Xcode", getXcodeVersion())
        } else {
            return (ProcessInfo.processInfo.processName, (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "")
        }
    }
    
    static func getCpuCount() -> Int {
        ProcessInfo.processInfo.processorCount
    }

    static func getAppearance() -> String {
        #if os(iOS) || os(tvOS) || os(watchOS)
            let appearance: String
            if #available(iOS 13.0, tvOS 13.0, *) {
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
            } else if #available(iOS 12.0, tvOS 12.0, *) {
                switch UIScreen.main.traitCollection.userInterfaceStyle {
                    case .dark:
                        appearance = "dark"
                    case .light:
                        appearance = "light"
                    case .unspecified:
                        appearance = "unspecified"
                    @unknown default:
                        appearance = "unknown"
                }
            } else {
                appearance = "light"
            }

            return appearance
        #else
            if #available(OSX 10.14, *) {
                return NSApp?.effectiveAppearance.name.rawValue ?? "light"
            } else {
                return "light"
            }
        #endif
    }


    #if os(iOS)
        static func getOrientation() -> String {
            let orientation: UIInterfaceOrientation
            if #available(iOS 13.0, *) {
                let scene = UIApplication.shared.connectedScenes
                            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
                orientation = scene?.interfaceOrientation ?? .portrait
            } else {
                orientation = UIApplication.shared.statusBarOrientation
            }
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
        #if os(iOS) || os(tvOS) || os(watchOS)
            return Locale.current.languageCode ?? "none"
        #else
            return NSLocale.current.languageCode ?? "none"
        #endif
    }
}
