/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi

/// Common attributes sanitizer for all features.
public struct AttributesSanitizer {
    public enum Constraints {
        /// Maximum number of nested levels in attribute name. E.g. `person.address.street` has 3 levels.
        /// If attribute name exceeds this number, extra levels are escaped by using `_` character (`one.two.(...).nine.ten_eleven_twelve`).
        static let maxNestedLevelsInAttributeName: Int = 10
        /// Maximum number of attributes in log.
        /// If this number is exceeded, extra attributes will be ignored.
        static let maxNumberOfAttributes: Int = 256
        /// Maximum number of characters the backend accepts per attribute value
        /// (and per span tag / metadata key). Longer string values are truncated.
        public static let maxAttributeValueLength: Int = 5_000
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
                Log.print("\(featureName) attribute '\(key)' was modified to '\(sanitizedName)' to match Datadog constraints."
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

    // MARK: - Attribute values sanitization

    /// Trims attribute values to `Constraints.maxAttributeValueLength` characters
    /// to match the backend per-tag length limit.
    func sanitizeValues(for attributes: [String: AttributeValue]) -> [String: AttributeValue] {
        attributes.mapValues { Self.trim($0) }
    }

    /// Trims a single attribute value to `Constraints.maxAttributeValueLength` characters.
    ///
    /// Numeric values (`.int` / `.double`) are sent as numbers and left unchanged.
    /// Every other value is serialized to its `description` (the same representation
    /// the encoders emit), so it is converted to `.string` here and truncated, ensuring
    /// the value that actually reaches the backend respects the length limit.
    static func trim(_ value: AttributeValue) -> AttributeValue {
        switch value {
        case .int, .double:
            return value
        default:
            let maxLength = Constraints.maxAttributeValueLength
            let string = value.description
            return .string(string.count > maxLength ? String(string.prefix(maxLength)) : string)
        }
    }
}
