/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import OpenTelemetryApi

@objc(DDTestSession)
public final class Session: NSObject, Encodable {
    let id: SpanId
    let name: String
    let startTime: Date
    public var resource: String
    public var testFramework: String
    var duration: UInt64
    var meta: [String: String] = [:]
    var metrics: [String: Double] = [:]
    var status: TestStatus
    
    private var _testRunsCount: Synced<UInt> = Synced(0)
    var testRunsCount: UInt { _testRunsCount.value }
    
    //var codeOwners: CodeOwners? = nil
    var configError: Bool = false
    
    init(name: String, command: String? = nil, startTime: Date? = nil) {
        self.duration = 0
        self.status = .pass
        self.name = name
        //self.codeOwners = nil
        self.testFramework = "Swift API"
        self.resource = name
        
        self.meta[DDTestTags.testCommand] = command
        
        try! DDTestMonitor.clock.sync()

        let beforeLoadingTime = DDTestMonitor.clock.now
        // TODO: Move it from the session init
        if DDTestMonitor.instance == nil {
            var success = false
            Log.measure(name: "installTestMonitor") {
                success = DDTestMonitor.installTestMonitor()
            }
            if !success {
                configError = true
            }
        }
        Log.debug("Install Test monitor time interval: \(DDTestMonitor.clock.now.timeIntervalSince(beforeLoadingTime))")
        
        DDTestMonitor.instance?.setupCrashHandler()
        
        let sessionStartTime = startTime ?? beforeLoadingTime
        if let crashedModuleInfo = DDTestMonitor.instance?.crashedModuleInfo {
            self.status = .fail
            self.id = crashedModuleInfo.crashedSessionId
            self.startTime = crashedModuleInfo.sessionStartTime ?? sessionStartTime
        } else {
            self.id = SpanId.random()
            self.startTime = sessionStartTime
        }
        Log.debug("Session loading time interval: \(DDTestMonitor.clock.now.timeIntervalSince(beforeLoadingTime))")
    }
    
    private func internalEnd(endTime: Date? = nil) {
        duration = (endTime ?? DDTestMonitor.clock.now).timeIntervalSince(startTime).toNanoseconds

        let sessionStatus: String = status.spanAttribute
        /// Export session event
        let sessionAttributes: [String: String] = [
            DDGenericTags.type: DDTagValues.typeSessionEnd,
            DDTestTags.testFramework: testFramework,
            DDTestTags.testStatus: sessionStatus,
            DDTestSuiteVisibilityTags.testSessionId: String(id.rawValue),
        ]
        meta.merge(sessionAttributes) { _, new in new }
        
        // Move to the global when we will support global metrics
        metrics.merge(DDTestMonitor.env.baseMetrics) { _, new in new }
        
        meta[DDTestSessionTags.testToolchain] = DDTestMonitor.env.platform.runtimeName.lowercased() + "-" + DDTestMonitor.env.platform.runtimeVersion
        
        meta[DDTestSessionTags.testCodeCoverageEnabled] = (DDTestMonitor.instance?.tia?.coverage != nil).spanAttribute
        
        let itrSkipped: UInt
        if let tia = DDTestMonitor.instance?.tia {
            itrSkipped = tia.skippedCount
            meta[DDTestSessionTags.testItrSkippingType] = DDTagValues.typeTest
            meta[DDTestSessionTags.testSkippingEnabled] = "true"
            metrics[DDTestSessionTags.testItrSkippingCount] = Double(itrSkipped)
        } else {
            itrSkipped = 0
            meta[DDTestSessionTags.testSkippingEnabled] = "false"
        }
        
        if itrSkipped == 0 {
            meta[DDItrTags.itrSkippedTests] = "false"
            meta[DDTestSessionTags.testItrSkipped] = "false"
            if let linesCovered = DDCoverageHelper.getLineCodeCoverage() {
                metrics[DDTestSessionTags.testCoverageLines] = linesCovered
            }
        } else {
            meta[DDItrTags.itrSkippedTests] = "true"
            meta[DDTestSessionTags.testItrSkipped] = "true"
        }
        
        if let efd = DDTestMonitor.instance?.efd {
            meta[DDEfdTags.testEfdEnabled] = "true"
            if efd.sessionFailed {
                meta[DDEfdTags.testEfdAbortReason] = DDTagValues.efdAbortFaulty
            }
        }
        
        DDTestMonitor.tracer.eventsExporter?.exportEvent(event: SessionEnvelope(self))
        Log.debug("Exported session_end event sessionId: \(self.id)")
        DDTestMonitor.tracer.flush()
    }
}

extension Session: TestSession {
    func set(tag name: String, value: any SpanAttributeConvertible) {
        meta[name] = value.spanAttribute
    }
    
    func set(metric name: String, value: Double) {
        metrics[name] = value
    }
    
    func set(failed reason: TestError?) {
        status = .fail
        if let error = reason {
            set(errorTags: error)
        }
    }
    
    func setSkipped() {
        status = .skip
    }
    
    func nextTestIndex() -> UInt {
        _testRunsCount.update { cnt in
            defer { cnt += 1 }
            return cnt
        }
    }
    
    func end(time: Date?) { end(endTime: time) }
}

/// Public interface for Session
public extension Session {
    /// Starts the test session
    /// - Parameters:
    ///   - name: name of the session
    ///   - command: Optional, test command that started this session
    ///   - startTime: Optional, the time where the session started
    @objc static func start(name: String, command: String? = nil, startTime: Date? = nil) -> Session {
        return Session(name: name, command: command, startTime: startTime)
    }

    @objc static func start(name: String) -> Session {
        return start(name: name, command: nil)
    }

    /// Ends the session
    /// - Parameters:
    ///   - endTime: Optional, the time where the session ended
    @objc(endWithTime:) func end(endTime: Date? = nil) {
        internalEnd(endTime: endTime)
    }

    @objc func end() {
        return end(endTime: nil)
    }

    /// Adds a extra tag or attribute to the test session, any number of tags can be reported
    /// - Parameters:
    ///   - key: The name of the tag, if a tag exists with the name it will be
    ///     replaced with the new value
    ///   - value: The value of the tag, can be a number or a string.
    @objc func setTag(key: String, value: Any) {
        trySet(tag: key, value: value)
    }

    /// Starts a module in this session
    /// - Parameters:
    ///   - name: name of the module
    ///   - startTime: Optional, the time where the module started
    @objc func moduleStart(name: String, startTime: Date? = nil) -> Module {
        return Module(name: name, session: self, startTime: startTime)
    }

    @objc func moduleStart(name: String) -> Module {
        return moduleStart(name: name, startTime: nil)
    }
}


extension Session {
    enum StaticCodingKeys: String, CodingKey {
        case test_session_id
        case name
        case resource
        case error
        case meta
        case metrics
        case start
        case duration
        case service
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StaticCodingKeys.self)
        try container.encode(id.rawValue, forKey: .test_session_id)
        try container.encode(startTime.timeIntervalSince1970.toNanoseconds, forKey: .start)
        try container.encode(duration, forKey: .duration)
        try container.encode(meta, forKey: .meta)
        try container.encode(metrics, forKey: .metrics)
        try container.encode(status == .fail ? 1 : 0, forKey: .error)
        try container.encode(name, forKey: .name)
        try container.encode(resource, forKey: .resource)
        try container.encode(DDTestMonitor.env.service, forKey: .service)
    }

    struct SessionEnvelope: Encodable {
        enum CodingKeys: String, CodingKey {
            case type
            case version
            case content
        }

        let version: Int = 1

        let type: String = DDTagValues.typeSessionEnd
        let content: Session

        init(_ content: Session) {
            self.content = content
        }
    }
}
