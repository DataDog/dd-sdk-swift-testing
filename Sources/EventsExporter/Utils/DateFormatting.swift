/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal protocol DateFormatterType {
    func string(from date: Date) -> String
}

extension ISO8601DateFormatter: DateFormatterType {}
extension DateFormatter: DateFormatterType {}

/// Date formatter producing `ISO8601` string representation of a given date.
/// Should be used to encode dates in messages send to the server.
internal let iso8601DateFormatter: DateFormatterType = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions.insert(.withFractionalSeconds)
    return formatter
}()
