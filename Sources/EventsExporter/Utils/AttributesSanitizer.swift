/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Common attributes sanitizer for all features.
internal struct AttributesSanitizer {
    enum Constraints {
        /// Maximum number of nested levels in attribute name. E.g. `person.address.street` has 3 levels.
        /// If attribute name exceeds this number, extra levels are escaped by using `_` character (`one.two.(...).nine.ten_eleven_twelve`).
        static let maxNestedLevelsInAttributeName: Int = 10
        /// Maximum number of attributes in log.
        /// If this number is exceeded, extra attributes will be ignored.
        static let maxNumberOfAttributes: Int = 256
    }

    let featureName: String

    // MARK: - Attribute keys sanitization

    /// Attribute keys can only have `Constants.maxNestedLevelsInAttributeName` levels.
    /// Extra levels are escaped with "_", e.g.:
    ///
    ///     one.two.three.four.five.six.seven.eight.nine.ten.eleven
    ///
    /// becomes:
    ///
    ///     one.two.three.four.five.six.seven.eight_nine_ten_eleven
    ///
    func sanitizeKeys<Value>(for attributes: [String: Value], prefixLevels: Int = 0) -> [String: Value] {
        let sanitizedAttributes: [(String, Value)] = attributes.map { key, value in
            let sanitizedName = sanitize(attributeKey: key, prefixLevels: prefixLevels)
            if sanitizedName != key {
                Swift.print(
                    """
                    [DatadogSDKTesting] +\(featureName) attribute '\(key)' was modified to '\(sanitizedName)' to match Datadog constraints.
                    """
                )
                return (sanitizedName, value)
            } else {
                return (key, value)
            }
        }
        return Dictionary(uniqueKeysWithValues: sanitizedAttributes)
    }

    private func sanitize(attributeKey: String, prefixLevels: Int = 0) -> String {
        var dotsCount = prefixLevels
        var sanitized = ""
        for char in attributeKey {
            if char == "." {
                dotsCount += 1
                sanitized.append(dotsCount >= Constraints.maxNestedLevelsInAttributeName ? "_" : char)
            } else {
                sanitized.append(char)
            }
        }
        return sanitized
    }
}
