/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import OpenTelemetryApi

protocol TestModel: AnyObject {
    var id: SpanId { get }
    var name: String { get }
    var startTime: Date { get }
    var duration: UInt64 { get }
    var status: TestStatus { get }
    
    func set(tag name: String, value: any SpanAttributeConvertible)
    func set(metric name: String, value: Double)
}

protocol TestContainer: TestModel {
    func set(failed reason: TestError?)
    func setSkipped()
    
    func end()
    func end(time: Date?)
}

extension TestContainer {
    func end() { end(time: nil) }
}

protocol TestSession: TestContainer {
    var testFramework: String { get }
    func nextTestIndex() -> UInt
}

protocol TestModule: TestContainer {
    var session: any TestSession { get }
    var localization: String { get }
}

protocol TestSuite: TestContainer {
    var session: any TestSession { get }
    var module: any TestModule { get }
    var localization: String { get }
}

extension TestSuite {
    var session: any TestSession { module.session }
}

protocol TestRun: TestModel {
    var session: any TestSession { get }
    var module: any TestModule { get }
    var suite: any TestSuite { get }
    
    func add(error: TestError)
    func add(benchmark name: String, samples: [Double], info: String?)
    
    func end(status: TestStatus)
    func end(status: TestStatus, time: Date?)
}

extension TestRun {
    var session: any TestSession { suite.session }
    var module: any TestModule { suite.module }
    
    func end(status: TestStatus) { end(status: status, time: nil) }
}

@objc(DDTestStatus)
public enum TestStatus: Int {
    case pass
    case fail
    case skip
}

extension TestStatus: SpanAttributeConvertible {
    var spanAttribute: String {
        switch self {
        case .pass: return DDTagValues.statusPass
        case .fail: return DDTagValues.statusFail
        case .skip: return DDTagValues.statusSkip
        }
    }
}

struct TestError {
    let type: String
    let message: String?
    let stack: String?
    let crashLog: String?
    
    init(type: String, message: String? = nil, stack: String? = nil, crashLog: String? = nil) {
        self.type = type
        self.message = message
        self.stack = stack
        self.crashLog = crashLog
    }
}

extension TestModel {
    /// saves error tags to the model
    internal func set(errorTags error: TestError) {
        set(tag: DDTags.errorType, value: error.type)
        if let message = error.message {
            set(tag: DDTags.errorMessage, value: message)
        }
        if let stack = error.stack {
            set(tag: DDTags.errorStack, value: stack)
        }
        if let crash = error.crashLog {
            set(tag: DDTags.errorCrashLog, value: crash)
        }
    }
    
    internal func trySet(tag key: String, value: Any) {
        if let value = value as? any BinaryFloatingPoint {
            self.set(metric: key, value: Double(value))
        } else if let value = value as? any BinaryInteger {
            self.set(metric: key, value: Double(value))
        } else if let value = value as? SpanAttributeConvertible {
            self.set(tag: key, value: value)
        }
    }
}
