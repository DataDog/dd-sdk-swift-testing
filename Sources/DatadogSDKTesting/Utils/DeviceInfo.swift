/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
#if canImport(WatchKit)
import WatchKit
#elseif canImport(UIKit)
import UIKit
#else
import SystemConfiguration
#endif
internal import EventsExporter

extension Device {
    /// Creates a `Device` populated from the current platform APIs.
    static var current: Device {
        Device(model: PlatformUtils.getDeviceModel(),
               osName: PlatformUtils.getDeviceName(),
               osVersion: PlatformUtils.getDeviceVersion())
    }
}

extension KernelInfo {
    /// Creates a `KernelInfo` from `uname(3)`.
    static var current: KernelInfo {
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
}

