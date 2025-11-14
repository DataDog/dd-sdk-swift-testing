/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

#if !os(macOS)
import UIKit
#else
import Foundation
import SystemConfiguration
#endif

/// Describes current mobile device.
public struct Device {
    // MARK: - Info

    var model: String
    var osName: String
    var osVersion: String

    public init(
        model: String,
        osName: String,
        osVersion: String)
    {
        self.model = model
        self.osName = osName
        self.osVersion = osVersion
    }

    #if !os(macOS)
    public init(uiDevice: UIDevice, processInfo: ProcessInfo) {
        self.init(
            model: uiDevice.model,
            osName: uiDevice.systemName,
            osVersion: uiDevice.systemVersion)
    }
    #else
    public init(processInfo: ProcessInfo) {
        self.init(
            model: "Mac",
            osName: processInfo.hostName,
            osVersion: processInfo.operatingSystemVersionString)
    }
    #endif

    /// Returns current mobile device  if `UIDevice` is available on this platform.
    /// On other platforms returns `nil`.
    public static var current: Device {
        #if os(macOS)
        return Device(processInfo: ProcessInfo.processInfo)
        #elseif os(iOS) && !targetEnvironment(simulator)
        // Real device
        return Device(uiDevice: UIDevice.current, processInfo: ProcessInfo.processInfo)
        #else
        // iOS Simulator or tvOS - battery monitoring doesn't work on Simulator, so return "always OK" value
        return Device(
            model: UIDevice.current.model,
            osName: UIDevice.current.systemName,
            osVersion: UIDevice.current.systemVersion)
        #endif
    }
}
