/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import XCTest

#if !os(macOS)
import UIKit
#else
import Foundation
import SystemConfiguration
#endif

@testable import OpenTelemetryExporter

class DeviceTests: XCTestCase {
    func testWhenRunningOnMobile_itReturnsDevice() {
        XCTAssertNotNil(Device.current)
    }

    #if !os(macOS) && !targetEnvironment(macCatalyst)
    func testWhenRunningOnMobile_itUsesUIDeviceInfo() {
        let uiDevice = UIDeviceMock(
            model: "model mock",
            systemName: "system name mock",
            systemVersion: "system version mock"
        )
        let device = Device(uiDevice: uiDevice, processInfo: ProcessInfo())

        XCTAssertEqual(device.model, uiDevice.model)
        XCTAssertEqual(device.osName, uiDevice.systemName)
        XCTAssertEqual(device.osVersion, uiDevice.systemVersion)
    }
    #endif // os(iOS) && !targetEnvironment(macCatalyst)
}
