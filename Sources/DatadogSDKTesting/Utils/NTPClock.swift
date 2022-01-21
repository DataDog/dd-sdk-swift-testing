/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
@_implementationOnly import OpenTelemetrySdk

class NTPClock: Clock {
    let ntpOffset: TimeInterval

    init() {
        let ntpServer = NTPServer.default
        do {
            try ntpServer.sync()
            let serverOffset = ntpServer.offset
            if serverOffset.isFinite {
                ntpOffset = serverOffset
            } else {
                ntpOffset = 0
                Log.debug("NTP server invalid time")
            }

        } catch {
            ntpOffset = 0
            Log.debug("NTP server fail to connect")
        }
    }

    var now: Date {
        let current = Date()
        return current.addingTimeInterval(ntpOffset)
    }
}
