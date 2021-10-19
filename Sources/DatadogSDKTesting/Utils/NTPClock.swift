/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
@_implementationOnly import Kronos
@_implementationOnly import OpenTelemetrySdk

class NTPClock: OpenTelemetrySdk.Clock {
    private var lastOffset: TimeInterval
    init() {
        Kronos.Clock.sync()
        let currentDate = Date()
        if let date = Kronos.Clock.now {
            lastOffset = date.timeIntervalSince(currentDate)
        } else {
            lastOffset = 0
        }
    }

    var now: Date {
        if Thread.isMainThread {
            let currentDate = Date()
            if let date = Kronos.Clock.now {
                lastOffset = date.timeIntervalSince(currentDate)
            } else {
                lastOffset = 0
            }
        }
        return Date().addingTimeInterval(lastOffset)
    }
}
