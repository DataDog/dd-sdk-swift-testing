/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import OpenTelemetryApi

@objc public class DDTestModule: NSObject, Encodable {
    let session: DDTestSession
    let bundleName = ""
    var id: SpanId
    let startTime: Date
    var duration: UInt64
    var meta: [String: String] = [:]
    var metrics: [String: Double] = [:]
    var status: DDTestStatus
    var localization: String
    var configError = false
    private(set) var itrSkipped = false
    var linesCovered: Double?
    
    let functionInfo: FunctionMap
//    static var bundleFunctionInfo = FunctionMap()
//    static var codeOwners: CodeOwners?

    var name: String { bundleName }
    var testFramework: String { session.testFramework }
    var codeOwners: CodeOwners? { session.codeOwners }
    var crashedInfo: CrashedSessionInformation? { session.crashedInfo }
    var currentExecutionOrder: Int { session.currentExecutionOrder }
    var service: String { session.service }

    init(session: DDTestSession, bundleName: String, startTime: Date?) {
        self.duration = 0
        self.status = .pass
        self.bundleName = bundleName
        self.session = session

        let beforeLoadingTime = DDTestMonitor.clock.now
        
        var functionInfo = FunctionMap()
#if targetEnvironment(simulator) || os(macOS)
        if !DDTestMonitor.config.disableSourceLocation {
            DDTestMonitor.instance?.instrumentationWorkQueue.addOperation {
                Log.debug("Create test bundle DSYM file for test source location")
                Log.measure(name: "createDSYMFileIfNeeded") {
                    DDSymbolicator.createDSYMFileIfNeeded(forImageName: bundleName)
                }
                Log.measure(name: "testFunctionsInModule") {
                    functionInfo = FileLocator.testFunctionsInModule(bundleName)
                }
            }
        }
#endif
        Log.measure(name: "waiting InstrumentationQueue") {
            DDTestMonitor.instance?.instrumentationWorkQueue.waitUntilAllOperationsAreFinished()
        }
        
        self.functionInfo = functionInfo
        
        let moduleStartTime = startTime ?? beforeLoadingTime
        if let crashedInfo = session.crashedInfo {
            self.status = .fail
            self.id = crashedInfo.crashedModuleId
            self.startTime = crashedInfo.moduleStartTime ?? moduleStartTime
        } else {
            self.id = SpanId.random()
            self.startTime = moduleStartTime
        }
        self.localization = PlatformUtils.getLocalization()
        Log.debug("Module loading time interval: \(DDTestMonitor.clock.now.timeIntervalSince(beforeLoadingTime))")
    }

    private func internalEnd(endTime: Date? = nil) {
        duration = (endTime ?? DDTestMonitor.clock.now).timeIntervalSince(startTime).toNanoseconds

        // If there is a Sanitizer message, we fail the module so error can be shown
        if let sanitizerInfo = SanitizerHelper.getSaniziterInfo() {
            status = .fail
            meta[DDTags.errorType] = "Sanitizer Error"
            meta[DDTags.errorStack] = sanitizerInfo
        }

        /// Export module event
        let defaultAttributes: [String: String] = [
            DDGenericTags.type: DDTagValues.typeModuleEnd,
            DDTestSuiteVisibilityTags.testModuleId: String(id.rawValue),
            DDTestTags.testModule: bundleName,
            DDTestTags.testFramework: testFramework,
            DDTestTags.testStatus: status.tagValue,
        ]

        meta.merge(DDTestMonitor.baseConfigurationTags) { _, new in new }
        meta.merge(defaultAttributes) { _, new in new }
        meta.merge(DDTestMonitor.env.gitAttributes) { _, new in new }
        meta.merge(DDTestMonitor.env.ciAttributes) { _, new in new }
        meta[DDUISettingsTags.uiSettingsModuleLocalization] = localization
        
        meta[DDItrTags.itrSkippedTests] = itrSkipped ? "true" : "false"
        meta[DDTestSessionTags.testSkippingEnabled] = (DDTestMonitor.instance?.itr != nil) ? "true" : "false"
        meta[DDTestSessionTags.codeCoverageEnabled] = (DDTestMonitor.instance?.coverageHelper != nil) ? "true" : "false"
        if !itrSkipped {
            if let llvmProfilePath = DDTestMonitor.envReader.get(env: "LLVM_PROFILE_FILE", String.self) {
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
            metrics[DDTestSuiteVisibilityTags.testCoverageLines] = linesCovered
        }
        DDTestMonitor.tracer.eventsExporter?.exportEvent(event: DDTestModuleEnvelope(self))
        Log.debug("Exported module_end event moduleId: \(self.id)")
        session.module(ended: self)
    }
    
    var moduleId: (session: SpanId, module: SpanId) { (session.id, id) }
    
    func test(started test: DDTest, in suite: DDTestSuite) {
        session.test(started: test, in: self, suite: suite)
    }
    
    func test(updated test: DDTest, in suite: DDTestSuite) {
        session.test(updated: test, in: self, suite: suite)
    }
    
    func test(ended test: DDTest, in suite: DDTestSuite) {
        session.test(ended: test, in: self, suite: suite)
    }
    
    func suite(started suite: DDTestSuite) {}
    
    func suite(ended suite: DDTestSuite) {
        if case .fail = suite.status { status = .fail }
        if suite.itrSkipped { itrSkipped = true }
    }
}

/// Public interface for DDTestModule
public extension DDTestModule {
    /// Ends the module
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

    /// Starts a suite in this module
    /// - Parameters:
    ///   - name: name of the suite
    ///   - startTime: Optional, the time where the suite started
    @objc func suiteStart(name: String, startTime: Date? = nil) -> DDTestSuite {
        DDTestSuite(name: name, module: self, startTime: startTime)
    }

    @objc func suiteStart(name: String) -> DDTestSuite {
        suiteStart(name: name, startTime: nil)
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
        try container.encode(meta[DDTags.service], forKey: .service)
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
