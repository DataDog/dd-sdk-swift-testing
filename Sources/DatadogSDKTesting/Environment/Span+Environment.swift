/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import OpenTelemetryApi

protocol SpanAttributeConvertible {
    var spanAttribute: String { get }
}

extension Int: SpanAttributeConvertible {
    var spanAttribute: String { String(self, radix: 10) }
}

extension String: SpanAttributeConvertible {
    var spanAttribute: String { self }
}

extension Bool: SpanAttributeConvertible {
    var spanAttribute: String { self ? "true" : "false" }
}

extension Date: SpanAttributeConvertible {
    var spanAttribute: String { ISO8601DateFormatter().string(from: self) }
}

extension URL: SpanAttributeConvertible {
    var spanAttribute: String {
        if var components = URLComponents(url: self, resolvingAgainstBaseURL: false) {
            components.user = nil
            components.password = nil
            return components.string ?? self.absoluteString
        } else {
            return self.absoluteString
        }
    }
}

extension Span {
    func addTags(from env: Environment) {
        for tag in env.tags {
            setAttribute(key: tag.key, value: tag.value)
        }
        if let workspace = env.workspacePath {
            setAttribute(key: DDCITags.ciWorkspacePath, value: workspace)
        }
        for attr in env.gitAttributes {
            setAttribute(key: attr.key, value: attr.value)
        }
        for attr in env.ciAttributes {
            setAttribute(key: attr.key, value: attr.value)
        }
    }
}
