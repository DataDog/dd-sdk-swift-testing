/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import OpenTelemetryApi

@objc public enum DDTestStatus: Int {
    case pass
    case fail
    case skip
}

@objc public class DDTestSession: NSObject, Encodable {
    let id: SpanId
    let name: String
    let startTime: Date
    let configError: Bool
    let testFramework: String
    let service: String
    let crashedInfo: CrashedSessionInformation?
    
    private(set) var duration: UInt64
    private(set) var status: DDTestStatus
    private(set) var meta: [String: String] = [:]
    private(set) var metrics: [String: Double] = [:]
    private(set) var itrSkipped: Bool
    private(set) var codeOwners: CodeOwners? = nil
    
    var resource: String
    
    private let executionLock = NSLock()
    private var privateCurrentExecutionOrder = 0
    var currentExecutionOrder: Int {
        executionLock.lock()
        defer {
            privateCurrentExecutionOrder += 1
            executionLock.unlock()
        }
        return privateCurrentExecutionOrder
    }
    
    init(name: String, service: String, testFramework: String = "Swift API", command: String? = nil, startTime: Date? = nil) {
        self.status = .pass
        self.duration = 0
        self.name = name
        self.testFramework = testFramework
        self.resource = "\(testFramework) session"
        self.itrSkipped = false
        self.service = service
        
        try! DDTestMonitor.clock.sync()

        let beforeLoadingTime = DDTestMonitor.clock.now
        if DDTestMonitor.instance == nil {
            //DDTestMonitor.baseConfigurationTags[DDTestTags.testBundle] = bundleName
            var success = false
            Log.measure(name: "installTestMonitor") {
                success = DDTestMonitor.installTestMonitor()
            }
            self.configError = !success
        } else {
            self.configError = false
        }
        Log.debug("Install Test monitor time interval: \(DDTestMonitor.clock.now.timeIntervalSince(beforeLoadingTime))")

        if !DDTestMonitor.config.disableCrashHandler {
            Log.measure(name: "DDCrashesInstall") {
                DDCrashes.install(disableMach: DDTestMonitor.config.disableMachCrashHandler)
            }
        }
        self.crashedInfo = DDTestMonitor.instance?.crashedSessionInfo
        DDTestMonitor.instance?.crashedSessionInfo = nil
        
        let sessionStartTime = startTime ?? beforeLoadingTime
        if let crashInfo = crashedInfo {
            self.status = .fail
            self.id = crashInfo.crashedSessionId
            self.startTime = crashInfo.sessionStartTime ?? sessionStartTime
        } else {
            self.id = SpanId.random()
            self.startTime = sessionStartTime
        }
        Log.debug("Session loading time interval: \(DDTestMonitor.clock.now.timeIntervalSince(beforeLoadingTime))")
        
        let toolchain = DDTestMonitor.env.platform.runtimeName.lowercased() + "-" + DDTestMonitor.env.platform.runtimeVersion
        
        let defaultAttributes: [String: String] = [
            DDGenericTags.type: DDTagValues.typeSessionEnd,
            DDTestSuiteVisibilityTags.testSessionId: String(id.rawValue),
            DDTestTags.testFramework: testFramework,
            DDTestTags.testCommand: command ?? "test \(name)",
            DDTestSessionTags.testToolchain: toolchain
        ]
        
        meta.merge(DDTestMonitor.baseConfigurationTags) { _, new in new }
        meta.merge(defaultAttributes) { _, new in new }
        meta.merge(DDTestMonitor.env.gitAttributes) { _, new in new }
        meta.merge(DDTestMonitor.env.ciAttributes) { _, new in new }
        super.init()

#if targetEnvironment(simulator) || os(macOS)
        if !DDTestMonitor.config.disableSourceLocation {
            DDTestMonitor.instance?.instrumentationWorkQueue.addOperation {
                if let workspacePath = DDTestMonitor.env.workspacePath {
                    Log.measure(name: "createCodeOwners") {
                        self.codeOwners = CodeOwners(workspacePath: URL(fileURLWithPath: workspacePath))
                    }
                }
            }
        }
#endif
    }

//    init(testModule: DDTestModule) {
//        // Create a fake session from module Info
//        self.id = testModule.sessionId
//        self.name = "\(testModule.testFramework).session"
//        self.resource = "\(testModule.bundleName) session"
//        self.startTime = testModule.startTime
//        self.duration = testModule.duration
//        self.metrics = testModule.metrics
//        self.status = testModule.status
//
//        // Copy module tags
//        self.meta = testModule.meta
//
//        // Modify tags that are different
//        self.meta[DDGenericTags.type] = DDTagValues.typeSessionEnd
//
//        // Remove tags that dont belong to sessions
//        //self.meta[DDTestTags.testBundle] = nil
//        //self.meta[DDTestSuiteVisibilityTags.testModuleId] = nil
//        //self.meta[DDUISettingsTags.uiSettingsModuleLocalization] = nil
//
//        // Add spacific tags for sessions
//        self.meta[DDTestTags.testCommand] = "test \(testModule.bundleName)"
//        self.meta[DDTestSessionTags.testToolchain] = DDTestMonitor.env.platform.runtimeName.lowercased() + "-" + DDTestMonitor.env.platform.runtimeVersion
//    }
    
    private func internalEnd(endTime: Date? = nil) {
        duration = (endTime ?? DDTestMonitor.clock.now).timeIntervalSince(startTime).toNanoseconds
        meta[DDTestTags.testStatus] = status.tagValue
        meta[DDItrTags.itrSkippedTests] = itrSkipped ? "true" : "false"
        
        DDTestMonitor.tracer.eventsExporter?.exportEvent(event: DDTestSession.DDTestSessionEnvelope(self))
        Log.debug("Exported session_end event sessionId: \(self.id)")
        
        if let coverageHelper = DDTestMonitor.instance?.coverageHelper {
            /// We need to wait for all the traces to be written to the backend before exiting
            coverageHelper.coverageWorkQueue.maxConcurrentOperationCount = ProcessInfo.processInfo.activeProcessorCount
            coverageHelper.coverageWorkQueue.waitUntilAllOperationsAreFinished()
        }

        DDTestMonitor.tracer.flush()
        DDTestMonitor.instance?.gitUploadQueue.waitUntilAllOperationsAreFinished()
    }
    
    func test(started test: DDTest, in module: DDTestModule, suite: DDTestSuite) {
        DDTestMonitor.instance?.currentTest = test
        if let data = test.spanData {
            let simpleSpan = SimpleSpanData(spanData: data, moduleStartTime: module.startTime, suiteStartTime: suite.startTime)
            DDCrashes.setCustomData(customData: SimpleSpanSerializer.serializeSpan(simpleSpan: simpleSpan))
        }
    }
    
    func test(updated test: DDTest, in module: DDTestModule, suite: DDTestSuite) {
        if let data = test.spanData {
            let simpleSpan = SimpleSpanData(spanData: data, moduleStartTime: module.startTime, suiteStartTime: suite.startTime)
            DDCrashes.setCustomData(customData: SimpleSpanSerializer.serializeSpan(simpleSpan: simpleSpan))
        }
    }
    
    func test(ended test: DDTest, in module: DDTestModule, suite: DDTestSuite) {
        DDTestMonitor.instance?.currentTest = nil
        DDCrashes.setCustomData(customData: Data())
    }
    
    func module(started module: DDTestModule) {}
    
    func module(ended module: DDTestModule) {
        if case .fail = module.status { status = .fail }
        if module.itrSkipped { itrSkipped = true }
    }
}

/// public interface for DDTestSession
extension DDTestSession {
    /// Starts the session
    /// - Parameters:
    ///   - name: name of the test session.
    ///   - startTime: Optional, the time where the session started
    @objc static func start(name: String, service: String, startTime: Date? = nil) -> DDTestSession {
        DDTestSession(name: name, service: service, startTime: startTime)
    }

    @objc static func start(name: String, service: String) -> DDTestSession {
        start(name: name, service: service, startTime: nil)
    }
    
    /// Ends the session
    /// - Parameters:
    ///   - endTime: Optional, the time where the module ended
    @objc(endWithTime:) func end(endTime: Date? = nil) {
        internalEnd(endTime: endTime)
    }

    @objc func end() { end(endTime: nil) }

    /// Adds a extra tag or attribute to the test module, any number of tags can be reported
    /// - Parameters:
    ///   - key: The name of the tag, if a tag exists with the name it will be
    ///     replaced with the new value
    ///   - value: The value of the tag, can be a number or a string.
    @objc func setTag(key: String, value: Any) {
        meta[key] = AttributeValue(value)?.description
    }
    
    /// Adds a extra metric to the test session, any number of metrics can be reported
    /// - Parameters:
    ///   - key: The name of the metric, if a metric exists with the name it will be
    ///     replaced with the new value
    ///   - value: The value of the metric.
    @objc func setMetric(key: String, value: Double) {
        metrics[key] = value
    }
    
    /// Starts the module
    /// - Parameters:
    ///   - bundleName: name of the module or bundle to test.
    ///   - startTime: Optional, the time where the module started
    @objc func moduleStart(bundleName: String, startTime: Date? = nil) -> DDTestModule {
        DDTestModule(session: self, bundleName: bundleName, startTime: startTime)
    }

    @objc func moduleStart(bundleName: String) -> DDTestModule {
        moduleStart(bundleName: bundleName, startTime: nil)
    }
}

extension DDTestSession {
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
        try container.encode(meta[DDTags.service], forKey: .service)
    }

    struct DDTestSessionEnvelope: Encodable {
        enum CodingKeys: String, CodingKey {
            case type
            case version
            case content
        }

        let version: Int = 1

        let type: String = DDTagValues.typeSessionEnd
        let content: DDTestSession

        init(_ content: DDTestSession) {
            self.content = content
        }
    }
}


extension DDTestStatus {
    var tagValue: String {
        switch self {
        case .skip: return DDTagValues.statusSkip
        case .fail: return DDTagValues.statusFail
        case .pass: return DDTagValues.statusPass
        }
    }
}
