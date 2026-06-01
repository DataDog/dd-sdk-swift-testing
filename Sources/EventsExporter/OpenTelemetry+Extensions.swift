/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

// MARK: - Resource accessors

/// Typed accessors over the OTel semantic-convention attribute keys we care
/// about. The encoders read service / version / environment / SDK info from
/// `SpanData.resource` instead of carrying them on the exporter's own struct.
public extension Resource {
    var applicationName: String? {
        get { attributes[SemanticConventions.Service.name.rawValue]?.description }
        set { attributes[SemanticConventions.Service.name.rawValue] = newValue.map { .string($0) } }
    }

    var applicationVersion: String? {
        get { attributes[SemanticConventions.Service.version.rawValue]?.description }
        set { attributes[SemanticConventions.Service.version.rawValue] = newValue.map { .string($0) } }
    }

    var service: String? {
        get { attributes[SemanticConventions.Service.namespace.rawValue]?.description }
        set { attributes[SemanticConventions.Service.namespace.rawValue] = newValue.map { .string($0) } }
    }

    var sdkName: String? {
        get { attributes[SemanticConventions.Telemetry.sdkName.rawValue]?.description }
        set { attributes[SemanticConventions.Telemetry.sdkName.rawValue] = newValue.map { .string($0) } }
    }

    var sdkLanguage: String? {
        get { attributes[SemanticConventions.Telemetry.sdkLanguage.rawValue]?.description }
        set { attributes[SemanticConventions.Telemetry.sdkLanguage.rawValue] = newValue.map { .string($0) } }
    }

    var sdkVersion: String? {
        get { attributes[SemanticConventions.Telemetry.sdkVersion.rawValue]?.description }
        set { attributes[SemanticConventions.Telemetry.sdkVersion.rawValue] = newValue.map { .string($0) } }
    }

    var environment: String? {
        get { attributes[SemanticConventions.Deployment.environmentName.rawValue]?.description }
        set { attributes[SemanticConventions.Deployment.environmentName.rawValue] = newValue.map { .string($0) } }
    }

    /// Datadog telemetry namespace hint for metrics produced by a meter provider.
    /// The metric exporter uses this as the per-series namespace when it's valid for
    /// the target payload. The value should match a `TelemetryMetric.Namespace` /
    /// `TelemetryDistribution.Namespace` raw value (e.g. `"tracers"`, `"general"`).
    var telemetryNamespace: String? {
        get { attributes["dd.telemetry.namespace"]?.description }
        set { attributes["dd.telemetry.namespace"] = newValue.map { .string($0) } }
    }
}

// MARK: - Test-attribute accessors on SpanData / AttributeValue dictionaries

public extension SpanData {
    var testSessionId: SpanId? { attributes.testSessionId }
    var testSuiteId: SpanId? { attributes.testSuiteId }
    var testModuleId: SpanId? { attributes.testModuleId }
}

public extension Dictionary where Key == String, Value == AttributeValue {
    var testSessionId: SpanId? {
        get { decodeSpanIdAttribute("test_session_id") }
        set { self["test_session_id"] = newValue.map { .string($0.hexString) } }
    }

    var testSuiteId: SpanId? {
        get { decodeSpanIdAttribute("test_suite_id") }
        set { self["test_suite_id"] = newValue.map { .string($0.hexString) } }
    }

    var testModuleId: SpanId? {
        get { decodeSpanIdAttribute("test_module_id") }
        set { self["test_module_id"] = newValue.map { .string($0.hexString) } }
    }
    
    var type: String? {
        get { self["type"]?.description }
        set { self["type"] = newValue.map { .string($0) } }
    }
    
    var resource: String? {
        get { self["resource"]?.description }
        set { self["resource"] = newValue.map { .string($0) } }
    }
    
    var itrCorrelationId: String? {
        get { self["itr_correlation_id"]?.description }
        set { self["itr_correlation_id"] = newValue.map { .string($0) } }
    }

    private func decodeSpanIdAttribute(_ key: String) -> SpanId? {
        guard let raw = self[key]?.description else { return nil }
        let id = SpanId(fromHexString: raw)
        return id == .invalid ? nil : id
    }
}

// MARK: - SpanExporterResultCode / ExportResult combinators

/// Lets call sites do `code1 && code2 && code3` without unpacking each
/// `success` case manually. Used to combine flush results across the
/// per-feature sub-exporters.
internal protocol ResultCodeCompatible {
    var isSuccess: Bool { get }
}

extension ResultCodeCompatible {
    static func && (lhs: Self, rhs: ResultCodeCompatible) -> Bool {
        lhs.isSuccess && rhs.isSuccess
    }

    static func && (lhs: Bool, rhs: Self) -> Bool {
        lhs && rhs.isSuccess
    }

    static func && (lhs: Self, rhs: Bool) -> Bool {
        lhs.isSuccess && rhs
    }
}

extension SpanExporterResultCode: ResultCodeCompatible {
    var isSuccess: Bool { self == .success }
}

extension ExportResult: ResultCodeCompatible {
    var isSuccess: Bool { self == .success }
}
