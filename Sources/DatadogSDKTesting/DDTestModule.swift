/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
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
    var itrSkipped = false
    var linesCovered: Double?
    var anyTestExecuted = false

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

    init(bundleName: String, startTime: Date?) {
        self.duration = 0
        self.status = .pass
        self.bundleName = bundleName

        let beforeLoadingTime = DDTestMonitor.clock.now
        if DDTestMonitor.instance == nil {
            DDTestMonitor.baseConfigurationTags[DDTestTags.testBundle] = bundleName
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
        if !DDTestMonitor.env.disableSourceLocation {
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

        if !DDTestMonitor.env.disableCrashHandler {
            Log.measure(name: "DDCrashesInstall") {
                DDCrashes.install()
            }
        }
        let moduleStartTime = startTime ?? beforeLoadingTime
        self.id = DDTestMonitor.instance?.crashedModuleInfo?.crashedModuleId ?? SpanId.random()
        self.sessionId = DDTestMonitor.instance?.crashedModuleInfo?.crashedSessionId ?? SpanId.random()
        self.startTime = DDTestMonitor.instance?.crashedModuleInfo?.moduleStartTime ?? moduleStartTime
        self.localization = PlatformUtils.getLocalization()

        Log.debug("Module loading time interval: \(DDTestMonitor.clock.now.timeIntervalSince(beforeLoadingTime))")
    }

    func internalEnd(endTime: Date? = nil) {
        if DDTestMonitor.instance?.crashedModuleInfo != nil && anyTestExecuted == false {
            //The module started after a crash and no test was executed because of ITR dont report it
            DDTestMonitor.tracer.flush()
            return
        }
        
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

        if let llvmProfilePath = DDEnvironmentValues.getEnvVariable("LLVM_PROFILE_FILE") {
            let profileFolder = URL(fileURLWithPath: llvmProfilePath).deletingLastPathComponent()
            // Locate proper file
            if let enumerator = FileManager.default.enumerator(at: profileFolder, includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants) {
                for element in enumerator {
                    if let file = element as? URL, file.pathExtension == "profraw" {
                        let coverage = DDCoverageHelper.getModuleCoverage(profrawFile: file, binaryImagePaths: BinaryImages.binaryImagesPath)
                        linesCovered = coverage?.data.first?.totals.lines.percent
                        break
                    }
                }
            }
        }
        /// Export module event
        let defaultAttributes: [String: String] = [
            DDGenericTags.type: DDTagValues.typeModuleEnd,
            DDGenericTags.language: "swift",
            DDDeviceTags.deviceName: DDTestMonitor.env.deviceName,
            DDTestTags.testSuite: bundleName,
            DDTestTags.testFramework: testFramework,
            DDTestTags.testStatus: moduleStatus,
            DDTestSuiteVisibilityTags.testModuleId: String(id.rawValue),
        ]

        meta.merge(DDTestMonitor.baseConfigurationTags) { _, new in new }
        meta.merge(defaultAttributes) { _, new in new }
        meta.merge(DDEnvironmentValues.gitAttributes) { _, new in new }
        meta.merge(DDEnvironmentValues.ciAttributes) { _, new in new }
        meta[DDUISettingsTags.uiSettingsModuleLocalization] = localization
        meta[DDItrTags.itrSkippedTests] = itrSkipped ? "true" : "false"
        meta[DDTestModuleTags.testSkippingEnabled] = (DDTestMonitor.instance?.itr != nil) ? "true" : "false"
        meta[DDTestModuleTags.codeCoverageEnabled] = (DDTestMonitor.instance?.coverageHelper != nil) ? "true" : "false"
        if !itrSkipped {
            metrics[DDTestSuiteVisibilityTags.testCoverageLines] = linesCovered
        }
        DDTestMonitor.tracer.eventsExporter?.exportEvent(event: DDTestModuleEnvelope(self))
        Log.debug("Exported module_end event moduleId: \(self.id)")

        let testSession = DDTestSession(testModule: self)
        DDTestMonitor.tracer.eventsExporter?.exportEvent(event: DDTestSession.DDTestSessionEnvelope(testSession))
        Log.debug("Exported session_end event sessionId: \(self.sessionId)")

        if let coverageHelper = DDTestMonitor.instance?.coverageHelper {
            /// We need to wait for all the traces to be written to the backend before exiting
            coverageHelper.coverageWorkQueue.maxConcurrentOperationCount = ProcessInfo.processInfo.activeProcessorCount
            coverageHelper.coverageWorkQueue.waitUntilAllOperationsAreFinished()
        }

        DDTestMonitor.tracer.flush()
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
        anyTestExecuted = true
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
        try container.encode(DDTestMonitor.env.ddService ?? DDTestMonitor.env.getRepositoryName() ?? "unknown-swift-repo", forKey: .service)
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
