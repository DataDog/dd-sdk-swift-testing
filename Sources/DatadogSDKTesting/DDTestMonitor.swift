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

    static var tracer = DDTracer()
    static var env = Environment(config: config, env: envReader, log: Log.instance)
    static var config: Config = Config(env: envReader)
    
    static var envReader: EnvironmentReader = ProcessEnvironmentReader()
    
    static var sessionId: String = { envReader["XCTestSessionIdentifier"] ?? UUID().uuidString }()
    
    static let tracerVersion = Bundle.sdk.version ?? "unknown"

    static var cacheManager: CacheManager? = {
        do {
            return try CacheManager(environment: env.environment, session: sessionId,
                                    commit: env.git.commitSHA, debug: config.extraDebugCodeCoverage)
        } catch {
            Log.print("Cache Manager initialization failed: \(error)")
            return nil
        }
    }()
    
    var networkInstrumentation: DDNetworkInstrumentation?
    var injectHeaders: Bool = false
    var recordPayload: Bool = false
    var maxPayloadSize: UInt
    var launchNotificationObserver: NSObjectProtocol?
    var didBecomeActiveNotificationObserver: NSObjectProtocol?
    var isRumActive: Bool = false
    let messageChannelUUID: String

    var crashedModuleInfo: CrashedModuleInformation?

    let instrumentationWorkQueue = OperationQueue()
    private let testOptimizationSetupQueue = OperationQueue()
    let gitUploadQueue = OperationQueue()

    static let developerMachineHostName: String = try! Spawn.output("hostname")

    var coverageHelper: DDCoverageHelper?
    var gitUploader: GitUploader?
    var itr: IntelligentTestRunner?
    
    var failedTestRetriesCount: UInt = 0
    var failedTestRetriesTotalCount: UInt = 0
    var efd: EarlyFlakeDetectionService? = nil

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

        Log.measure(name: "startTestOptimization") {
            DDTestMonitor.instance?.startTestOptimization()
        }
        return true
    }
    
    static func removeTestMonitor() {
        DDTestMonitor.instance = nil
        Log.debug("Clearing monitor")
        try? DDSymbolicator.dsymFilesDir.delete()
        DDTestMonitor.cacheManager = nil
    }

    init() {
        Log.debug("Config:\n\(DDTestMonitor.config)")
        Log.debug("Environment:\n\(DDTestMonitor.env)")
        maxPayloadSize = DDTestMonitor.config.maxPayloadSize
        messageChannelUUID = DDTestMonitor.config.messageChannelUUID ?? UUID().uuidString
        
        if DDTestMonitor.config.isBinaryUnderUITesting {
            launchNotificationObserver = NotificationCenter.default.addObserver(
                forName: launchNotificationName,
                object: nil, queue: nil)
            { _ in
                /// As crash reporter is initialized in testBundleWillStart() method, we initialize it here
                /// because dont have test observer
                if !DDTestMonitor.config.disableCrashHandler {
                    DDCrashes.install(folder: try! DDTestMonitor.cacheManager!.common(feature: "crashes"),
                                      disableMach: DDTestMonitor.config.disableMachCrashHandler)
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
                    commitFolder: try? DDTestMonitor.cacheManager?.commit(feature: "git")
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

    func startTestOptimization() {
        var tracerBackendConfig: TracerSettings? = nil
        itr = nil
        coverageHelper = nil
        efd = nil
        let service = DDTestMonitor.env.service
        
        guard let branch = DDTestMonitor.env.git.branch,
              let commit = DDTestMonitor.env.git.commitSHA else {
            Log.print("Unknown branch and commit. ITR and EFD can't be started")
            return
        }
        
        guard let repository = DDTestMonitor.env.git.repositoryURL?.spanAttribute else {
            Log.print("Unknown repository URL. ITR and EFD can't be started")
            return
        }
        
        let getTracerConfig = { (log: String) in
            if let eventsExporter = DDTestMonitor.tracer.eventsExporter {
                return Log.measure(name: log) {
                    eventsExporter.tracerSettings(
                        service: service,
                        env: DDTestMonitor.env.environment,
                        repositoryURL: repository,
                        branch: branch,
                        sha: commit,
                        testLevel: .test,
                        configurations: DDTestMonitor.env.baseConfigurations,
                        customConfigurations: DDTestMonitor.config.customConfigurations
                    )
                }
            } else {
                return nil
            }
        }
        
        let updateTracerConfig = BlockOperation { [self] in
            tracerBackendConfig = getTracerConfig("Get Tracer Config")
            guard var config = tracerBackendConfig else {
                Log.debug("Tracer Config request failed")
                return
            }
            Log.debug("Tracer Config: \(config)")
            if config.itr.requireGit {
                Log.debug("ITR requires Git upload")
                gitUploadQueue.waitUntilAllOperationsAreFinished()
                if isGitUploadSucceded {
                    config = getTracerConfig("Get Tracer Config after git upload") ?? config
                    Log.debug("Tracer config: \(config)")
                } else {
                    Log.print("ITR requires Git but Git Upload failed. Disabling ITR")
                    config.itr.itrEnabled = false
                }
                tracerBackendConfig = config
            }
            if config.flakyTestRetriesEnabled && DDTestMonitor.config.testRetriesEnabled {
                failedTestRetriesCount = DDTestMonitor.config.testRetriesTestRetryCount
                failedTestRetriesTotalCount = DDTestMonitor.config.testRetriesTotalRetryCount
            }
        }
        testOptimizationSetupQueue.addOperation(updateTracerConfig)
        
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
                    guard let settings = tracerBackendConfig?.itr,
                          settings.itrEnabled && settings.testsSkipping
                    else {
                        Log.debug("ITR Disabled")
                        return
                    }
                    guard let folder = try? DDTestMonitor.cacheManager?.session(feature: "itr") else {
                        Log.print("ITR init failed. Can't create cache folder")
                        return
                    }
                    // Activate Intelligent Test Runner
                    itr = IntelligentTestRunner(configurations: DDTestMonitor.env.baseConfigurations,
                                                custom: DDTestMonitor.config.customConfigurations,
                                                folder: folder)
                    itr?.start()
                }
                itrSetup.addDependency(updateTracerConfig)
                testOptimizationSetupQueue.addOperation(itrSetup)
            }
        }
        
        if DDTestMonitor.config.codeCoverageEnabled {
            let coverageSetup = BlockOperation { [self] in
                guard let settings = tracerBackendConfig?.itr, settings.codeCoverage else {
                    Log.debug("Coverage Disabled")
                    return
                }
                // Activate Coverage
                Log.debug("Coverage Enabled")
                guard let temp = try? DDTestMonitor.cacheManager?.temp(feature: "coverage") else {
                    Log.print("Coverage init failed. Can't create temp directory.")
                    coverageHelper = nil
                    return
                }
                guard let exporter = DDTestMonitor.tracer.eventsExporter else {
                    Log.print("Coverage init failed. Exporter is nil.")
                    coverageHelper = nil
                    return
                }
                coverageHelper = DDCoverageHelper(storagePath: temp, exporter: exporter,
                                                  workspacePath: DDTestMonitor.env.workspacePath,
                                                  priority: DDTestMonitor.config.codeCoveragePriority,
                                                  debug: DDTestMonitor.config.extraDebugCodeCoverage)
            }
            coverageSetup.addDependency(updateTracerConfig)
            testOptimizationSetupQueue.addOperation(coverageSetup)
        }
        
        if DDTestMonitor.config.efdEnabled {
            let efdSetup = BlockOperation { [self] in
                guard let config = tracerBackendConfig?.efd, config.enabled else {
                    Log.debug("Early Flake Detection Disabled")
                    return
                }
                // Activate EFD
                Log.debug("Early Flake Detection Enabled")
                guard let eventsExporter = DDTestMonitor.tracer.eventsExporter else {
                    Log.print("EFD init failed. Exporter is nil")
                    efd = nil
                    return
                }
                guard let cache = try? DDTestMonitor.cacheManager?.session(feature: "efd") else {
                    Log.print("EFD init failed. Can't create cache directiry.")
                    efd = nil
                    return
                }
                efd = EarlyFlakeDetection(repository: repository, service: service, environment: DDTestMonitor.env.environment,
                                          configurations: DDTestMonitor.env.baseConfigurations,
                                          custom: DDTestMonitor.config.customConfigurations,
                                          exporter: eventsExporter, cache: cache,
                                          slowTestRetries: config.slowTestRetries,
                                          faultySessionThreshold: config.faultySessionThreshold)
                efd?.start()
            }
            efdSetup.addDependency(updateTracerConfig)
            testOptimizationSetupQueue.addOperation(efdSetup)
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
    
    func ensureTestOptimizationStarted() {
        testOptimizationSetupQueue.waitUntilAllOperationsAreFinished()
    }
}
