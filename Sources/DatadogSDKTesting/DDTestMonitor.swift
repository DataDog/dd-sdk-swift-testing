/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@_implementationOnly import EventsExporter
@_implementationOnly import OpenTelemetryApi
@_implementationOnly import OpenTelemetrySdk

#if canImport(UIKit)
    import UIKit
    let launchNotificationName = UIApplication.didFinishLaunchingNotification
    let didBecomeActiveNotificationName = UIApplication.didBecomeActiveNotification
#elseif canImport(Cocoa)
    import Cocoa
    let launchNotificationName = NSApplication.didFinishLaunchingNotification
    let didBecomeActiveNotificationName = NSApplication.didBecomeActiveNotification
#endif

struct CrashedModuleInformation {
    var crashedSessionId: SpanId
    var crashedModuleId: SpanId
    var crashedSuiteId: SpanId
    var crashedSuiteName: String
    var moduleStartTime: Date?
    var suiteStartTime: Date?
}

internal class DDTestMonitor {
    static var instance: DDTestMonitor?
    static var clock: Clock = DDTestMonitor.config.disableNTPClock ? DateClock() : NTPClock()

    static let defaultPayloadSize = 1024

    static var tracer = DDTracer()
    static var env = Environment(config: config, env: envReader, log: Log.instance)
    static var config: Config = Config(env: envReader)
    
    static var envReader: EnvironmentReader = ProcessEnvironmentReader()

    static var dataPath: Directory? = try? Directory(withSubdirectoryPath: "com.datadog.civisibility")
    static var cacheDir: Directory? = try? dataPath?.createSubdirectory(path: "caches")
    static var commitFolder: Directory? = {
        guard let commit = DDTestMonitor.env.git.commitSHA else { return nil }
        return try? DDTestMonitor.cacheDir?.createSubdirectory(path: commit)
    }()

    var networkInstrumentation: DDNetworkInstrumentation?
    var injectHeaders: Bool = false
    var recordPayload: Bool = false
    var maxPayloadSize: Int = defaultPayloadSize
    var launchNotificationObserver: NSObjectProtocol?
    var didBecomeActiveNotificationObserver: NSObjectProtocol?
    var isRumActive: Bool = false
    let messageChannelUUID: String

    var crashedModuleInfo: CrashedModuleInformation?

    let instrumentationWorkQueue = OperationQueue()
    private let itrWorkQueue = OperationQueue()
    let gitUploadQueue = OperationQueue()

    static let developerMachineHostName: String = try! Spawn.output("hostname")

    static var baseConfigurationTags = [
        DDOSTags.osPlatform: env.platform.osName,
        DDOSTags.osArchitecture: env.platform.osArchitecture,
        DDOSTags.osVersion: env.platform.osVersion,
        DDDeviceTags.deviceModel: env.platform.deviceModel,
        DDRuntimeTags.runtimeName: env.platform.runtimeName,
        DDRuntimeTags.runtimeVersion: env.platform.runtimeVersion,
        DDUISettingsTags.uiSettingsLocalization: env.platform.localization,
    ]

    var coverageHelper: DDCoverageHelper?
    var gitUploader: GitUploader?
    var itr: IntelligentTestRunner?

    var rLock = NSRecursiveLock()
    private var privateCurrentTest: DDTest?
    var currentTest: DDTest? {
        get {
            rLock.lock()
            defer { rLock.unlock() }
            return privateCurrentTest
        }
        set {
            rLock.lock()
            defer { rLock.unlock() }
            privateCurrentTest = newValue
        }
    }
    
    private var isGitUploadSucceded: Bool = false
    private var serverTestingPort: CFMessagePort? = nil

    static func installTestMonitor() -> Bool {
        guard DDTestMonitor.config.apiKey != nil else {
            Log.print("A Datadog API key is required. DD_API_KEY environment value is missing.")
            return false
        }
        if DDTestMonitor.env.sourceRoot == nil {
            Log.print("SRCROOT is not properly set")
        }
        Log.print("Library loaded and active. Instrumenting tests.")
        DDTestMonitor.instance = DDTestMonitor()
        Log.measure(name: "startInstrumenting") {
            DDTestMonitor.instance?.startInstrumenting()
        }

        Log.measure(name: "startGitUpload") {
            DDTestMonitor.instance?.startGitUpload()
        }

        Log.measure(name: "startITR") {
            DDTestMonitor.instance?.startITR()
        }
        return true
    }

    init() {
        messageChannelUUID = DDTestMonitor.config.messageChannelUUID ?? UUID().uuidString
        
        if DDTestMonitor.config.isBinaryUnderUITesting {
            launchNotificationObserver = NotificationCenter.default.addObserver(
                forName: launchNotificationName,
                object: nil, queue: nil)
            { _ in
                /// As crash reporter is initialized in testBundleWillStart() method, we initialize it here
                /// because dont have test observer
                if !DDTestMonitor.config.disableCrashHandler {
                    DDCrashes.install(disableMach: DDTestMonitor.config.disableMachCrashHandler)
                    let launchedSpan = DDTestMonitor.tracer.createSpanFromLaunchContext()
                    let simpleSpan = SimpleSpanData(spanData: launchedSpan.toSpanData())
                    DDCrashes.setCustomData(customData: SimpleSpanSerializer.serializeSpan(simpleSpan: simpleSpan))
                }
            }

            #if targetEnvironment(simulator) || os(macOS)
                didBecomeActiveNotificationObserver = NotificationCenter.default.addObserver(
                    forName: didBecomeActiveNotificationName,
                    object: nil, queue: nil)
                { _ in
                    var data = [DDUISettingsTags.uiSettingsAppearance: PlatformUtils.getAppearance(),
                                DDUISettingsTags.uiSettingsLocalization: PlatformUtils.getLocalization()]
                    #if os(iOS)
                        data[DDUISettingsTags.uiSettingsOrientation] = PlatformUtils.getOrientation()
                    #endif
                    guard let port = self.testingPort else {
                        Log.debug("DatadogTestingPort CFMessagePortCreateRemote failed")
                        return
                    }
                    guard let encoded = try? JSONSerialization.data(withJSONObject: data) else {
                        Log.debug("Json encoding failed for: \(data)")
                        return
                    }
                    let timeout: CFTimeInterval = 1.0
                    let status = CFMessagePortSendRequest(port,
                                                          DDCFMessageID.setCustomTags,
                                                          encoded as CFData,
                                                          timeout,
                                                          timeout,
                                                          nil,
                                                          nil)
                    if status == kCFMessagePortSuccess {
                        Log.debug("DatadogTestingPort Success: \(data)")
                    } else {
                        Log.debug("DatadogTestingPort Error: \(status)")
                    }
                }
            #endif
        }
    }

    func startGitUpload() {
        /// Check Git is up to date and no local changes
        let workspace = DDTestMonitor.env.workspacePath ?? ""
        guard DDTestMonitor.env.isCI || GitUploader.statusUpToDate(workspace: workspace, log: Log.instance) else {
            Log.print("Git status is not up to date")
            return
        }

        DDTestMonitor.instance?.gitUploadQueue.addOperation {
            if DDTestMonitor.config.gitUploadEnabled {
                Log.debug("Git Upload Enabled")
                guard let exporter = DDTestMonitor.tracer.eventsExporter else {
                    Log.print("GitUpload error: event exporter is nil")
                    self.isGitUploadSucceded = false
                    return
                }
                DDTestMonitor.instance?.gitUploader = GitUploader(
                    log: Log.instance, exporter: exporter, workspace: workspace,
                    commitFolder: DDTestMonitor.commitFolder
                )
            } else {
                Log.debug("Git Upload Disabled")
                self.isGitUploadSucceded = false
                return
            }
            
            guard let commit = DDTestMonitor.env.git.commitSHA else {
                Log.print("Commit SHA is empty. GitUpload failed")
                self.isGitUploadSucceded = false
                return
            }
            
            self.isGitUploadSucceded = DDTestMonitor.instance?.gitUploader?.sendGitInfo(
                repositoryURL: DDTestMonitor.env.git.repositoryURL, commit: commit
            ) ?? false
        }
    }

    func startITR() {
        var itrBackendConfig: ITRSettings? = nil
        itr = nil
        coverageHelper = nil
        
        guard let branch = DDTestMonitor.env.git.branch,
              let commit = DDTestMonitor.env.git.commitSHA else {
            Log.print("Unknown branch and commit. ITR can't be started")
            return
        }
        
        let getItrConfig = { (log: String) in
            if let service = DDTestMonitor.config.service ?? DDTestMonitor.env.git.repositoryName,
               let eventsExporter = DDTestMonitor.tracer.eventsExporter
            {
                return Log.measure(name: log) {
                    eventsExporter.itrSetting(service: service,
                                              env: DDTestMonitor.env.environment,
                                              repositoryURL: DDTestMonitor.env.git.repositoryURL?.spanAttribute ?? "",
                                              branch: branch,
                                              sha: commit,
                                              testLevel: .test,
                                              configurations: DDTestMonitor.baseConfigurationTags,
                                              customConfigurations: DDTestMonitor.config.customConfigurations)
                }
            } else {
                return nil
            }
        }
        
        let updateItrSettings = BlockOperation { [self] in
            itrBackendConfig = getItrConfig("Get ITR Config")
            Log.debug("ITR config: \(String(describing: itrBackendConfig))")
            if itrBackendConfig?.requireGit ?? false {
                Log.debug("ITR requires Git upload")
                gitUploadQueue.waitUntilAllOperationsAreFinished()
                guard isGitUploadSucceded else {
                    Log.print("ITR requires Git but Git Upload failed. Disabling ITR")
                    itrBackendConfig = nil
                    return
                }
                itrBackendConfig = getItrConfig("Get ITR Config after git upload")
                Log.debug("ITR config: \(String(describing: itrBackendConfig))")
            }
        }
        itrWorkQueue.addOperation(updateItrSettings)
        
        if DDTestMonitor.config.itrEnabled {
            let isExcluded = { (branch: String) in
                let excludedBranches = DDTestMonitor.config.excludedBranches
                if excludedBranches.contains(branch) {
                    Log.debug("Excluded branch: \(branch)")
                    return true
                }
                let match = excludedBranches
                    .filter { $0.hasSuffix("*") }
                    .map { $0.dropLast() }
                    .first { branch.hasPrefix($0) }
                if let wildcard = match {
                    Log.debug("Excluded branch: \(branch) with wildcard: \(wildcard)*")
                    return true
                }
                return false
            }
            
            if !isExcluded(branch) {
                let itrSetup = BlockOperation { [self] in
                    // Activate Intelligent Test Runner
                    if itrBackendConfig?.testsSkipping ?? false {
                        Log.debug("ITR Enabled")
                        
                        itr = IntelligentTestRunner(configurations: DDTestMonitor.baseConfigurationTags)
                        itr?.start()
                    } else {
                        Log.debug("ITR Disabled")
                    }
                }
                itrSetup.addDependency(updateItrSettings)
                itrWorkQueue.addOperation(itrSetup)
            }
        }
        
        if DDTestMonitor.config.coverageEnabled {
            let coverageSetup = BlockOperation { [self] in
                // Activate Coverage
                if itrBackendConfig?.codeCoverage ?? false {
                    Log.debug("Coverage Enabled")
                    coverageHelper = DDCoverageHelper()
                } else {
                    Log.debug("Coverage Disabled")
                    coverageHelper = nil
                }
                
            }
            coverageSetup.addDependency(updateItrSettings)
            itrWorkQueue.addOperation(coverageSetup)
        }
    }

    func startInstrumenting() {
        guard !DDTestMonitor.config.disableTestInstrumenting else {
            return
        }

        Log.measure(name: "DDTracer") {
            _ = DDTestMonitor.tracer
        }

        if !DDTestMonitor.config.disableNetworkInstrumentation {
            Log.measure(name: "startNetworkAutoInstrumentation") {
                startNetworkAutoInstrumentation()
                if !DDTestMonitor.config.disableHeadersInjection {
                    injectHeaders = true
                }
                if DDTestMonitor.config.enableRecordPayload {
                    recordPayload = true
                }
                if let maxPayload = DDTestMonitor.config.maxPayloadSize {
                    maxPayloadSize = maxPayload
                }
            }
        }
        if DDTestMonitor.config.enableStdoutInstrumentation {
            instrumentationWorkQueue.addOperation { [self] in
                Log.measure(name: "startStdoutCapture") {
                    startStdoutCapture()
                }
            }
        }
        if DDTestMonitor.config.enableStderrInstrumentation {
            instrumentationWorkQueue.addOperation { [self] in
                Log.measure(name: "startStderrCapture") {
                    startStderrCapture()
                }
            }
        }
    }

    func startNetworkAutoInstrumentation() {
        networkInstrumentation = DDNetworkInstrumentation()
    }

    func startHeaderInjection() {
        injectHeaders = true
    }

    func stopHeaderInjection() {
        injectHeaders = false
    }

    func startStdoutCapture() {
        StdoutCapture.startCapturing()
    }

    func stopStdoutCapture() {
        StdoutCapture.stopCapturing()
    }

    func startStderrCapture() {
        StderrCapture.startCapturing()
    }

    func stopStderrCapture() {
        StderrCapture.stopCapturing()
    }
    
    var rumPort: CFMessagePort? {
        guard isRumActive else { return nil }
        return CFMessagePortCreateRemote(nil, "DatadogRUMTestingPort-\(messageChannelUUID)" as CFString)
    }
    
    private var testingPort: CFMessagePort? {
        CFMessagePortCreateRemote(nil, "DatadogTestingPort-\(messageChannelUUID)" as CFString)
    }

    func startAttributeListener() {
        rLock.lock()
        defer { rLock.unlock() }
        
        guard serverTestingPort == nil else { return }
        
        func attributeCallback(port: CFMessagePort?, msgid: Int32, data: CFData?, info: UnsafeMutableRawPointer?) -> Unmanaged<CFData>? {
            switch msgid {
                case DDCFMessageID.setCustomTags:
                    if let data = data as Data?,
                       let decoded = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                    {
                        decoded.forEach {
                            DDTestMonitor.instance?.currentTest?.setTag(key: $0.key, value: $0.value)
                        }
                    }
                case DDCFMessageID.enableRUM:
                    DDTestMonitor.instance?.isRumActive = true
                    DDTestMonitor.instance?.currentTest?.setTag(key: DDTestTags.testIsRUMActive, value: String("true"))
                case DDCFMessageID.forceFlush:
                    Log.debug("CFMessagePort forceFlush")
                default:
                    Log.debug("CFMessagePort unknown message")
            }

            return nil
        }

        serverTestingPort = CFMessagePortCreateLocal(
            nil, "DatadogTestingPort-\(messageChannelUUID)" as CFString,
            attributeCallback, nil, nil
        )
        guard let port = serverTestingPort else {
            Log.debug("DatadogTestingPort CFMessagePortCreateLocal failed")
            return
        }
        let runLoopSource = CFMessagePortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, CFRunLoopMode.commonModes)
    }
    
    func ensureITRStarted() {
        itrWorkQueue.waitUntilAllOperationsAreFinished()
    }
}
