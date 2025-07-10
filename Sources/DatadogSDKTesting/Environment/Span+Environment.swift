/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import EventsExporter
@_implementationOnly import OpenTelemetryApi

protocol SpanAttributeConvertible {
    var spanAttribute: String { get }
}

extension Int: SpanAttributeConvertible {
    var spanAttribute: String { String(self, radix: 10) }
}

extension UInt: SpanAttributeConvertible {
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
            if components.scheme == nil && components.password == nil {
                // fix for ssh urls
                return self.absoluteString
            }
            components.user = nil
            components.password = nil
            return components.string ?? self.absoluteString
        } else {
            return self.absoluteString
        }
    }
}

extension SpanMetadata {
    init(libraryVersion: String, env: Environment, capabilities: SDKCapabilities) {
        self.init(libraryVersion: libraryVersion,
                  tags: env.baseConfigurations,
                  git: env.gitAttributes,
                  ci: env.ciAttributes,
                  sessionName: env.sessionName,
                  isUserProvidedService: env.isUserProvidedService,
                  capabilities: capabilities)
        for tag in env.tags {
            self[string: .test, tag.key] = tag.value
        }
    }
}
