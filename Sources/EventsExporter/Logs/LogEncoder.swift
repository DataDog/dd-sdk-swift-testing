/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

internal struct LogAttributes {
    /// Log attributes received from the user. They are subject for sanitization.
    let userAttributes: [String: Encodable]
    /// Log attributes added internally by the SDK. They are not a subject for sanitization.
    let internalAttributes: [String: Encodable]?
}

/// `Encodable` representation of log. It gets sanitized before encoding.
internal struct DDLog: Encodable {
    internal enum TracingAttributes {
        static let traceID = "dd.trace_id"
        static let spanID = "dd.span_id"
    }

    enum Status: String, Encodable {
        case debug
        case info
        case notice
        case warn
        case error
        case critical
        
        init(status: Severity) {
            switch status {
            case .trace, .trace2, .trace3, .trace4: self = .notice
            case .debug, .debug2, .debug3, .debug4: self = .debug
            case .info, .info2, .info3, .info4: self = .info
            case .warn, .warn2, .warn3, .warn4: self = .warn
            case .error, .error2, .error3, .error4: self = .error
            case .fatal, .fatal2, .fatal3, .fatal4: self = .critical
            }
        }
    }

    let date: Date
    let status: Status
    let message: String
    let serviceName: String
    let environment: String
    let loggerName: String
    let loggerVersion: String
    let threadName: String
    let applicationVersion: String
    let attributes: LogAttributes
    let tags: [String]?
    let hostname: String = ProcessInfo.processInfo.hostName

    func encode(to encoder: Encoder) throws {
        let sanitizedLog = LogSanitizer().sanitize(log: self)
        try LogEncoder().encode(sanitizedLog, to: encoder)
    }

    internal init(date: Date, status: DDLog.Status, message: String, serviceName: String, environment: String,
                  loggerName: String, loggerVersion: String, threadName: String,
                  applicationVersion: String, attributes: LogAttributes, tags: [String]?)
    {
        self.date = date
        self.status = status
        self.message = message
        self.serviceName = serviceName
        self.environment = environment
        self.loggerName = loggerName
        self.loggerVersion = loggerVersion
        self.threadName = threadName
        self.applicationVersion = applicationVersion
        self.attributes = attributes
        self.tags = tags
    }
    
    internal init(spanId: SpanId, traceId: TraceId,
                  timestamp: Date, status: Status,
                  message: String, resource: Resource,
                  attributes: [String: AttributeValue])
    {
        var attributes = attributes
        
        self.date = timestamp
        self.status = status
        self.message = message
        self.serviceName = resource.service ?? ""
        self.environment = resource.environment ?? ""
        self.loggerName = resource.sdkName ?? ""
        self.loggerVersion = resource.sdkVersion ?? ""
        self.threadName = attributes.removeValue(forKey: SemanticConventions.Thread.name.rawValue)?.description ?? "unknown"
        self.applicationVersion = resource.applicationVersion ?? ""

        let userAttributes: [String: Encodable] = attributes.mapValues {
            switch $0 {
                case let .string(value):
                    return value
                case let .bool(value):
                    return value
                case let .int(value):
                    return value
                case let .double(value):
                    return value
                case let .stringArray(value):
                    return value
                case let .boolArray(value):
                    return value
                case let .intArray(value):
                    return value
                case let .doubleArray(value):
                    return value
                default: fatalError("Found user attribute of unsupported type")
            }
        }
        
        // set tracing attributes
        let internalAttributes = [
            TracingAttributes.traceID: "\(traceId.rawLowerLong)",
            TracingAttributes.spanID: "\(spanId.rawValue)"
        ]
        
        self.attributes = LogAttributes(userAttributes: userAttributes, internalAttributes: internalAttributes)
        self.tags = nil // tags
    }

    internal init(event: SpanData.Event, span: SpanData) {
        var attributes = event.attributes
        
        self.init(spanId: span.spanId, traceId: span.traceId,
                  timestamp: event.timestamp,
                  status: Status(rawValue: attributes["status"]?.description ?? "info") ?? .info,
                  message: attributes.removeValue(forKey: "message")?.description ?? "Span event",
                  resource: span.resource,
                  attributes: attributes)
    }
    
    internal init(log: ReadableLogRecord, span: SpanContext) {
        var attributes = log.attributes
        
        self.init(spanId: span.spanId, traceId: span.traceId,
                  timestamp: log.observedTimestamp ?? log.timestamp,
                  status: log.severity.map { .init(status: $0) } ?? .info,
                  message: log.body?.description ?? attributes.removeValue(forKey: "message")?.description ?? log.eventName ?? "Log event",
                  resource: log.resource,
                  attributes: attributes)
    }
}

/// Encodes `Log` to given encoder.
internal struct LogEncoder {
    /// Coding keys for permanent `Log` attributes.
    enum StaticCodingKeys: String, CodingKey {
        case date
        case status
        case message
        case serviceName = "service"
        case tags = "ddtags"
        case hostname
        case product = "datadog.product"

        // MARK: - Application info

        case applicationVersion = "version"

        // MARK: - Logger info

        case loggerName = "logger.name"
        case loggerVersion = "logger.version"
        case threadName = "logger.thread_name"
    }

    /// Coding keys for dynamic `Log` attributes specified by user.
    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        init(_ string: String) { self.stringValue = string }
    }

    func encode(_ log: DDLog, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StaticCodingKeys.self)
        try container.encode(log.date, forKey: .date)
        try container.encode(log.status, forKey: .status)
        try container.encode(log.message, forKey: .message)
        try container.encode(log.serviceName, forKey: .serviceName)
        try container.encode(log.hostname, forKey: .hostname)

        // Encode logger info
        try container.encode(log.loggerName, forKey: .loggerName)
        try container.encode(log.loggerVersion, forKey: .loggerVersion)
        try container.encode(log.threadName, forKey: .threadName)

        // Encode application info
        try container.encode(log.applicationVersion, forKey: .applicationVersion)

        // Encode attributes...
        var attributesContainer = encoder.container(keyedBy: DynamicCodingKey.self)

        // ... first, user attributes ...
        let encodableUserAttributes = Dictionary(
            uniqueKeysWithValues: log.attributes.userAttributes.map { name, value in (name, EncodableValue(value)) }
        )
        try encodableUserAttributes.forEach { try attributesContainer.encode($0.value, forKey: DynamicCodingKey($0.key)) }

        // ... then, internal attributes:
        if let internalAttributes = log.attributes.internalAttributes {
            let encodableInternalAttributes = Dictionary(
                uniqueKeysWithValues: internalAttributes.map { name, value in (name, EncodableValue(value)) }
            )
            try encodableInternalAttributes.forEach { try attributesContainer.encode($0.value, forKey: DynamicCodingKey($0.key)) }
        }

        // Encode tags
        var tags = log.tags ?? []
        tags.append("env:\(log.environment)") // include default tag
        let tagsString = tags.joined(separator: ",")
        try container.encode(tagsString, forKey: .tags)
    }
}
