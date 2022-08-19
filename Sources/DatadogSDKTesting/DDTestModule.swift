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
    var bundleFunctionInfo = FunctionMap()
    var codeOwners: CodeOwners?
    var testFramework = "Swift API"
    var id: SpanId
    let startTime: Date
    var duration: UInt64
    var meta: [String: String] = [:]
    var status: DDTestStatus
    var localization: String
    var configError = false
    var configurationTags: [String: String]
    var itr: IntelligentTestRunner?

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
        let moduleStartTime = startTime ?? DDTestMonitor.clock.now
        self.duration = 0
        self.status = .pass
        if DDTestMonitor.instance == nil {
            let success = DDTestMonitor.installTestMonitor()
            if !success {
                configError = true
            }
        }

        self.bundleName = bundleName
#if targetEnvironment(simulator) || os(macOS)
        DDSymbolicator.createDSYMFileIfNeeded(forImageName: bundleName)
        bundleFunctionInfo = FileLocator.testFunctionsInModule(bundleName)
#endif
        if let workspacePath = DDTestMonitor.env.workspacePath {
            codeOwners = CodeOwners(workspacePath: URL(fileURLWithPath: workspacePath))
        }

        if !DDTestMonitor.env.disableCrashHandler {
            DDCrashes.install()
        }
        self.id = DDTestMonitor.instance?.crashedModuleInfo?.crashedModuleId ?? SpanId.random()
        self.startTime = DDTestMonitor.instance?.crashedModuleInfo?.moduleStartTime ?? moduleStartTime
        self.localization = PlatformUtils.getLocalization()

        configurationTags = [
            DDOSTags.osPlatform: DDTestMonitor.env.osName,
            DDOSTags.osArchitecture: DDTestMonitor.env.osArchitecture,
            DDOSTags.osVersion: DDTestMonitor.env.osVersion,
            DDDeviceTags.deviceName: DDTestMonitor.env.deviceName,
            DDDeviceTags.deviceModel: DDTestMonitor.env.deviceModel,
            DDRuntimeTags.runtimeName: DDTestMonitor.env.runtimeName,
            DDRuntimeTags.runtimeVersion: DDTestMonitor.env.runtimeVersion,
            DDTestTags.testBundle: bundleName,
            DDUISettingsTags.uiSettingsLocalization: PlatformUtils.getLocalization(),
        ]

        DDCoverageHelper.instance = DDCoverageHelper()

        let gitUploader = try? GitUploader()
        gitUploader?.start()

        itr = IntelligentTestRunner(configurations: configurationTags)
        itr?.start()
    }

    func internalEnd(endTime: Date? = nil) {
        duration = (endTime ?? DDTestMonitor.clock.now).timeIntervalSince(startTime).toNanoseconds

        let suiteStatus: String
        switch status {
            case .pass:
                suiteStatus = DDTagValues.statusPass
            case .fail:
                suiteStatus = DDTagValues.statusFail
            case .skip:
                suiteStatus = DDTagValues.statusSkip
        }

        /// Export module event
        let defaultAttributes: [String: String] = [
            DDGenericTags.type: DDTagValues.typeSuiteEnd,
            DDGenericTags.language: "swift",
            DDTestTags.testSuite: bundleName,
            DDTestTags.testFramework: testFramework,
            DDTestTags.testStatus: suiteStatus,
            DDTestModuleTags.testModuleId: String(id.rawValue)
        ]

        meta.merge(configurationTags) { _, new in new }
        meta.merge(defaultAttributes) { _, new in new }
        meta.merge(DDEnvironmentValues.gitAttributes) { _, new in new }
        meta.merge(DDEnvironmentValues.ciAttributes) { _, new in new }
        meta[DDUISettingsTags.uiSettingsModuleLocalization] = localization
        DDTestMonitor.tracer.eventsExporter?.exportEvent(event: DDTestModuleEnvelope(self))
        /// We need to wait for all the traces to be written to the backend before exiting
        DDTestMonitor.tracer.flush()
        DDCoverageHelper.instance?.coverageWorkQueue.waitUntilAllOperationsAreFinished()
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
        case test_module_id
        case start
        case duration
        case meta
        case error
        case name
        case resource
        case service
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StaticCodingKeys.self)
        try container.encode(id.rawValue, forKey: .test_module_id)
        try container.encode(startTime.timeIntervalSince1970.toNanoseconds, forKey: .start)
        try container.encode(duration, forKey: .duration)
        try container.encode(meta, forKey: .meta)
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
