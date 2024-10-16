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

public class DDTestModule: NSObject, Encodable {
    var bundleName = ""
    static var bundleFunctionInfo = FunctionMap()
    static var codeOwners: CodeOwners?
    var testFramework = "Swift API"
    var id: SpanId
    var sessionId: SpanId
    let startTime: Date
    var duration: UInt64
    var meta: [String: String] = [:]
    var metrics: [String: Double] = [:]
    var status: DDTestStatus
    var localization: String
    var configError = false
    
    private var _counters: Synced<Counters> = Synced(.init())
    
    var testRunsCount: UInt { _counters.value.allTestRuns }
    var skippedByITRTestsCount: UInt { _counters.value.skippedTests }
    var retriedByATRRunsCount: UInt { _counters.value.retryTestRuns }
    
    var efdTestsCounts: (newTests: UInt, knownTests: UInt) {
        _counters.use { ($0.newTests, $0.knownTests) }
    }
    
    var efdSessionFailed: Bool = false
    
    var linesCovered: Double? = nil

    init(bundleName: String, startTime: Date?) {
        self.duration = 0
        self.status = .pass
        self.bundleName = bundleName
        
        try! DDTestMonitor.clock.sync()

        let beforeLoadingTime = DDTestMonitor.clock.now
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

#if targetEnvironment(simulator) || os(macOS)
        if !DDTestMonitor.config.disableSourceLocation {
            DDTestMonitor.instance?.instrumentationWorkQueue.addOperation {
                Log.debug("Create test bundle DSYM file for test source location")
                Log.measure(name: "createDSYMFileIfNeeded") {
                    DDSymbolicator.createDSYMFileIfNeeded(forImageName: bundleName)
                }
                Log.measure(name: "testFunctionsInModule") {
                    DDTestModule.bundleFunctionInfo = FileLocator.testFunctionsInModule(bundleName)
                }
            }
            DDTestMonitor.instance?.instrumentationWorkQueue.addOperation {
                if let workspacePath = DDTestMonitor.env.workspacePath {
                    Log.measure(name: "createCodeOwners") {
                        DDTestModule.codeOwners = CodeOwners(workspacePath: URL(fileURLWithPath: workspacePath))
                    }
                }
            }
        }
#endif

        Log.measure(name: "waiting InstrumentationQueue") {
            DDTestMonitor.instance?.instrumentationWorkQueue.waitUntilAllOperationsAreFinished()
        }

        if !DDTestMonitor.config.disableCrashHandler {
            Log.measure(name: "DDCrashesInstall") {
                DDCrashes.install(
                    folder: try! DDTestMonitor.cacheManager!.session(feature: "crash"),
                    disableMach: DDTestMonitor.config.disableMachCrashHandler)
            }
        }
        let moduleStartTime = startTime ?? beforeLoadingTime
        if let crashedModuleInfo = DDTestMonitor.instance?.crashedModuleInfo {
            self.status = .fail
            self.id = crashedModuleInfo.crashedModuleId
            self.sessionId = crashedModuleInfo.crashedSessionId
            self.startTime = crashedModuleInfo.moduleStartTime ?? moduleStartTime
        } else {
            self.id = SpanId.random()
            self.sessionId = SpanId.random()
            self.startTime = moduleStartTime
        }
        self.localization = PlatformUtils.getLocalization()

        Log.debug("Module loading time interval: \(DDTestMonitor.clock.now.timeIntervalSince(beforeLoadingTime))")
    }

    @discardableResult
    func incrementSkipped() -> UInt {
        _counters.update { cnt in
            defer { cnt.skippedTests += 1 }
            return cnt.skippedTests
        }
    }
    
    func incrementTestRuns() -> UInt {
        _counters.update { cnt in
            defer { cnt.allTestRuns += 1 }
            return cnt.allTestRuns
        }
    }
    
    func incrementRetries(max: UInt) -> UInt? {
        _counters.update { cnt in
            cnt.retryTestRuns.checkedAdd(1, max: max).map {
                cnt.retryTestRuns = $0
                return $0
            }
        }
    }
    
    @discardableResult
    func incrementNewTests() -> UInt {
        _counters.update { cnt in
            defer { cnt.newTests += 1 }
            return cnt.allTestRuns
        }
    }
    
    func addExpectedTests(count: UInt) {
        _counters.update { cnt in
            cnt.knownTests += count
        }
    }
    
    private func internalEnd(endTime: Date? = nil) {
        duration = (endTime ?? DDTestMonitor.clock.now).timeIntervalSince(startTime).toNanoseconds

        let moduleStatus: String

        // If there is a Sanitizer message, we fail the module so error can be shown
        if let sanitizerInfo = SanitizerHelper.getSaniziterInfo() {
            moduleStatus = DDTagValues.statusFail
            meta[DDTags.errorType] = "Sanitizer Error"
            meta[DDTags.errorStack] = sanitizerInfo

        } else {
            switch status {
            case .pass:
                moduleStatus = DDTagValues.statusPass
            case .fail:
                moduleStatus = DDTagValues.statusFail
            case .skip:
                moduleStatus = DDTagValues.statusSkip
            }
        }

        /// Export module event
        let moduleAttributes: [String: String] = [
            DDGenericTags.type: DDTagValues.typeModuleEnd,
            DDTestTags.testModule: bundleName,
            DDTestTags.testFramework: testFramework,
            DDTestTags.testStatus: moduleStatus,
            DDTestSuiteVisibilityTags.testModuleId: String(id.rawValue),
        ]
        meta.merge(moduleAttributes) { _, new in new }
        
        // Move to the global when we will support global metrics
        metrics.merge(DDTestMonitor.env.baseMetrics) { _, new in new }
        
        meta[DDUISettingsTags.uiSettingsModuleLocalization] = localization
        meta[DDTestSessionTags.testCodeCoverageEnabled] = (DDTestMonitor.instance?.coverageHelper != nil) ? "true" : "false"
        
        let itrSkipped = self.skippedByITRTestsCount
        
        if DDTestMonitor.instance?.itr != nil {
            meta[DDTestSessionTags.testItrSkippingType] = DDTagValues.typeTest
            meta[DDTestSessionTags.testSkippingEnabled] = "true"
            metrics[DDTestSessionTags.testItrSkippingCount] = Double(itrSkipped)
        } else {
            meta[DDTestSessionTags.testSkippingEnabled] = "false"
        }
        
        if itrSkipped == 0 {
            meta[DDItrTags.itrSkippedTests] = "false"
            meta[DDTestSessionTags.testItrSkipped] = "false"
            if !DDTestMonitor.config.coverageMode.isPerTest {
                metrics[DDTestSessionTags.testCoverageLines] = DDCoverageHelper.getLineCodeCoverage()
            }
        } else {
            meta[DDItrTags.itrSkippedTests] = "true"
            meta[DDTestSessionTags.testItrSkipped] = "true"
        }
        
        if DDTestMonitor.instance?.efd != nil {
            meta[DDEfdTags.testEfdEnabled] = "true"
        }
        if efdSessionFailed {
            meta[DDEfdTags.testEfdAbortReason] = "faulty"
        }
        
        DDTestMonitor.tracer.eventsExporter?.exportEvent(event: DDTestModuleEnvelope(self))
        Log.debug("Exported module_end event moduleId: \(self.id)")

        let testSession = DDTestSession(testModule: self)
        DDTestMonitor.tracer.eventsExporter?.exportEvent(event: DDTestSession.DDTestSessionEnvelope(testSession))
        Log.debug("Exported session_end event sessionId: \(self.sessionId)")

        if let coverageHelper = DDTestMonitor.instance?.coverageHelper {
            /// We need to wait for all the traces to be written to the backend before exiting
            coverageHelper.coverageWorkQueue.maxConcurrentOperationCount = ProcessInfo.processInfo.activeProcessorCount
            coverageHelper.coverageWorkQueue.qualityOfService = .userInteractive
            coverageHelper.coverageWorkQueue.waitUntilAllOperationsAreFinished()
        }

        DDTestMonitor.tracer.flush()
        DDTestMonitor.instance?.gitUploadQueue.waitUntilAllOperationsAreFinished()
    }
    
    func checkEfdStatus(for test: DDTest, efd: EarlyFlakeDetection?) -> Bool {
        guard !efdSessionFailed, test.module.bundleName == bundleName else { return false }
        guard let known = efd?.knownTests, let threshold = efd?.faultySessionThreshold else { return false }
        // Calculate threshold
        let counts = efdTestsCounts
        let testsCount = max(Double(known.testCount), Double(counts.knownTests))
        let newTests = Double(counts.newTests)
        guard newTests <= threshold || ((newTests / testsCount) * 100.0) < threshold else {
            Log.print("Early Flake Detection Faulty Session detected!")
            efdSessionFailed = true
            return false
        }
        return known.isNew(test: test.name, in: test.suite.name, and: bundleName)
    }
}

/// Public interface for DDTestModule
public extension DDTestModule {
    /// Starts the module
    /// - Parameters:
    ///   - bundleName: name of the module or bundle to test.
    ///   - startTime: Optional, the time where the module started
    @objc static func start(bundleName: String, startTime: Date? = nil) -> DDTestModule {
        let module = DDTestModule(bundleName: bundleName, startTime: startTime)
        return module
    }

    @objc static func start(bundleName: String) -> DDTestModule {
        return start(bundleName: bundleName, startTime: nil)
    }

    /// Ends the module
    /// - Parameters:
    ///   - endTime: Optional, the time where the module ended
    @objc(endWithTime:) func end(endTime: Date? = nil) {
        internalEnd(endTime: endTime)
    }

    @objc func end() {
        return end(endTime: nil)
    }

    /// Adds a extra tag or attribute to the test module, any number of tags can be reported
    /// - Parameters:
    ///   - key: The name of the tag, if a tag exists with the name it will be
    ///     replaced with the new value
    ///   - value: The value of the tag, can be a number or a string.
    @objc func setTag(key: String, value: Any) {}

    /// Starts a suite in this module
    /// - Parameters:
    ///   - name: name of the suite
    ///   - startTime: Optional, the time where the suite started
    @objc func suiteStart(name: String, startTime: Date? = nil) -> DDTestSuite {
        let suite = DDTestSuite(name: name, module: self, startTime: startTime)
        return suite
    }

    @objc func suiteStart(name: String) -> DDTestSuite {
        return suiteStart(name: name, startTime: nil)
    }
}

extension DDTestModule {
    enum StaticCodingKeys: String, CodingKey {
        case test_session_id
        case test_module_id
        case start
        case duration
        case meta
        case metrics
        case error
        case name
        case resource
        case service
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StaticCodingKeys.self)
        try container.encode(sessionId.rawValue, forKey: .test_session_id)
        try container.encode(id.rawValue, forKey: .test_module_id)
        try container.encode(startTime.timeIntervalSince1970.toNanoseconds, forKey: .start)
        try container.encode(duration, forKey: .duration)
        try container.encode(meta, forKey: .meta)
        try container.encode(metrics, forKey: .metrics)
        try container.encode(status == .fail ? 1 : 0, forKey: .error)
        try container.encode("\(testFramework).module", forKey: .name)
        try container.encode("\(bundleName)", forKey: .resource)
        try container.encode(DDTestMonitor.config.service ?? DDTestMonitor.env.git.repositoryName ?? "unknown-swift-repo", forKey: .service)
    }

    struct DDTestModuleEnvelope: Encodable {
        enum CodingKeys: String, CodingKey {
            case type
            case version
            case content
        }

        let version: Int = 1

        let type: String = DDTagValues.typeModuleEnd
        let content: DDTestModule

        init(_ content: DDTestModule) {
            self.content = content
        }
    }
}

private extension DDTestModule {
    struct Counters {
        var skippedTests: UInt = 0
        var retryTestRuns: UInt = 0
        var allTestRuns: UInt = 0
        var newTests: UInt = 0
        var knownTests: UInt = 0
    }
}
