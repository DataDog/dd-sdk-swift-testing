//
//  OpenTelemetry+Extensions.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 24/11/2025.
//

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

public extension Resource {
    var applicationName: String? {
        get {
            attributes[SemanticConventions.Service.name.rawValue]?.description
        }
        set {
            attributes[SemanticConventions.Service.name.rawValue] = newValue.map { .string($0) }
        }
    }
    
    var applicationVersion: String? {
        get {
            attributes[SemanticConventions.Service.version.rawValue]?.description
        }
        set {
            attributes[SemanticConventions.Service.version.rawValue] = newValue.map { .string($0) }
        }
    }
    
    var service: String? {
        get {
            attributes[SemanticConventions.Service.namespace.rawValue]?.description
        }
        set {
            attributes[SemanticConventions.Service.namespace.rawValue] = newValue.map { .string($0) }
        }
    }
    
    var sdkName: String? {
        get {
            attributes[SemanticConventions.Telemetry.sdkName.rawValue]?.description
        }
        set {
            attributes[SemanticConventions.Telemetry.sdkName.rawValue] = newValue.map { .string($0) }
        }
    }
    
    var sdkLanguage: String? {
        get {
            attributes[SemanticConventions.Telemetry.sdkLanguage.rawValue]?.description
        }
        set {
            attributes[SemanticConventions.Telemetry.sdkLanguage.rawValue] = newValue.map { .string($0) }
        }
    }
    
    var sdkVersion: String? {
        get {
            attributes[SemanticConventions.Telemetry.sdkVersion.rawValue]?.description
        }
        set {
            attributes[SemanticConventions.Telemetry.sdkVersion.rawValue] = newValue.map { .string($0) }
        }
    }
    
    var environment: String? {
        get {
            attributes[SemanticConventions.Deployment.environmentName.rawValue]?.description
        }
        set {
            attributes[SemanticConventions.Deployment.environmentName.rawValue] = newValue.map { .string($0) }
        }
    }
}

public extension SpanData {
    var testSessionId: SpanId? { attributes.testSessionId }
    var testSuiteId: SpanId? { attributes.testSuiteId }
    var testModuleId: SpanId? { attributes.testModuleId }
}

public extension Dictionary where Key == String, Value == AttributeValue {
    var testSessionId: SpanId? {
        get {
            guard let sessionId = self["test_session_id"]?.description else {
                return nil
            }
            let id = SpanId(fromHexString: sessionId)
            return id == .invalid ? nil : id
        }
        set {
            self["test_session_id"] = newValue.map { .string($0.hexString) }
        }
    }
    
    var testSuiteId: SpanId? {
        get {
            guard let suiteId = self["test_suite_id"]?.description else {
                return nil
            }
            let id = SpanId(fromHexString: suiteId)
            return id == .invalid ? nil : id
        }
        set {
            self["test_suite_id"] = newValue.map { .string($0.hexString) }
        }
    }
    
    var testModuleId: SpanId? {
        get {
            guard let moduleId = self["test_module_id"]?.description else {
                return nil
            }
            let id = SpanId(fromHexString: moduleId)
            return id == .invalid ? nil : id
        }
        set {
            self["test_module_id"] = newValue.map { .string($0.hexString) }
        }
    }
}

protocol ResultCodeCompatible {
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
