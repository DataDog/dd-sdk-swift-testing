/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal let maxMetaStringValueLength = 5_000

internal func truncateMetaStringValue(_ value: String) -> String {
    value.count <= maxMetaStringValueLength ? value : String(value.prefix(maxMetaStringValueLength))
}

extension Dictionary where Key == String, Value == String {
    func truncatingMetaStringValues() -> [String: String] {
        var truncated: [String: String]?
        for (key, value) in self {
            let truncatedValue = truncateMetaStringValue(value)
            if truncatedValue != value, truncated == nil {
                truncated = self
            }
            truncated?[key] = truncatedValue
        }
        return truncated ?? self
    }
}
