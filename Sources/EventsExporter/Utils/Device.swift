/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// Describes the device on which the process is running.
/// Values are supplied by the caller (e.g. DatadogSDKTesting); this type
/// carries no platform-query logic.
public struct Device {
    public var name: String
    public var model: String
    public var osName: String
    public var osVersion: String
    public var osArchitecture: String

    public init(name: String, model: String, osName: String, osVersion: String, osArchitecture: String) {
        self.name = name
        self.model = model
        self.osName = osName
        self.osVersion = osVersion
        self.osArchitecture = osArchitecture
    }
}
