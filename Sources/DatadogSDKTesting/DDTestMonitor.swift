/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

internal import EventsExporter
internal import OpenTelemetryApi
internal import OpenTelemetrySdk

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
    var sessionStartTime: Date?
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
    
    // We can't calculate proper session and we need something to persist between executions
    // so we will use simulator id and boot time
    // for macOS machines we will try to use boot time too (no simulator info)
    static var sessionId: String = {
        let scheme = envReader["XCODE_SCHEME_NAME"] ?? Bundle.main.name
        let testPlan = envReader["XCODE_TEST_PLAN_NAME"] ?? Bundle.testBundle?.name ?? Bundle.main.name
        let bootTime: String = envReader["SIMULATOR_BOOT_TIME"] ??
            String(Int64(Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime))
        return "\(scheme)-\(testPlan)-\(bootTime)"
    }()
    
    static let tracerVersion = Bundle.sdk.version ?? "unknown"

    static var cacheManager: CacheManager? = {
        do {
            return try CacheManager(session: sessionId,
                                    commit: env.git.commit?.sha ?? "unknown-commit",
                                    debug: config.extraDebugCodeCoverage)
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
    
    var codeOwners: CodeOwners? = nil
    var bundleFunctionInfo: FunctionMap = .init()

    let instrumentationWorkQueue = OperationQueue()
    private let testOptimizationSetupQueue = OperationQueue()
    let gitUploadQueue = OperationQueue()

    static let developerMachineHostName: String = try! Spawn.output("hostname")

    // Advanced features
    var gitUploader: GitUploader? = nil
    var tia: TestImpactAnalysis? = nil
    var knownTests: KnownTests? = nil
    var efd: EarlyFlakeDetection? = nil
    var atr: AutomaticTestRetries? = nil
    var testManagement: TestManagement? = nil

    var rLock = NSRecursiveLock()
    private var privateCurrentTest: Test?
    var currentTest: Test? {
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
    private var isStopped: Bool = false

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
        
        DDTestMonitor.instance?.loadSourceCodeInfo()
        
        Log.measure(name: "startGitUpload") {
            DDTestMonitor.instance?.startGitUpload()
        }

        Log.measure(name: "startTestOptimization") {
            DDTestMonitor.instance?.startTestOptimization()
        }
        
        return true
    }
    
    static func removeTestMonitor() {
        DDTestMonitor.instance?.stop()
        DDTestMonitor.instance = nil
        Log.debug("Clearing monitor")
        try? DDSymbolicator.dsymFilesDir.delete()
        DDTestMonitor.cacheManager = nil
    }

    init() {
        Log.debug("Config:\n\(DDTestMonitor.config)")
        Log.debug("Environment:\n\(DDTestMonitor.env)")
        Log.debug("Session ID:\n\(DDTestMonitor.sessionId)")
        maxPayloadSize = DDTestMonitor.config.maxPayloadSize
        messageChannelUUID = DDTestMonitor.config.messageChannelUUID ?? UUID().uuidString
        
        if DDTestMonitor.config.isBinaryUnderUITesting {
            launchNotificationObserver = NotificationCenter.default.addObserver(
                forName: launchNotificationName,
                object: nil, queue: nil)
            { _ in
                /// As crash reporter is initialized in testBundleWillStart() method, we initialize it here
                /// because dont have test observer
                self.setupCrashHandler()
                let launchedSpan = DDTestMonitor.tracer.createSpanFromLaunchContext()
                let simpleSpan = SimpleSpanData(spanData: launchedSpan.toSpanData())
                DDCrashes.setCurrent(spanData: simpleSpan)
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
    
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        efd?.stop()
        atr?.stop()
        tia?.stop()
        knownTests?.stop()
        testManagement?.stop()
        DDTestMonitor.tracer.flush()
        let _ = DDTestMonitor.tracer.eventsExporter?.flush()
        gitUploadQueue.waitUntilAllOperationsAreFinished()
    }
    
    deinit {
        if !isStopped {
            Log.print("TestMonitor should be stopped before the deallocation")
        }
    }

    func startGitUpload() {
        /// Check Git is up to date and no local changes
        let workspace = DDTestMonitor.env.workspacePath ?? ""
        guard DDTestMonitor.env.isCI || GitUploader.statusUpToDate(workspace: workspace, log: Log.instance) else {
            Log.print("Git status is not up to date")
            return
        }
        
        guard let commit = DDTestMonitor.env.git.commit?.sha, commit != "" else {
            Log.print("Commit SHA is empty. Git upload failed")
            self.isGitUploadSucceded = false
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
            
            self.isGitUploadSucceded = DDTestMonitor.instance?.gitUploader?.sendGitInfo(
                repositoryURL: DDTestMonitor.env.git.repositoryURL, commit: commit
            ) ?? false
        }
    }

    func startTestOptimization() {
        var tracerBackendConfig: TracerSettings? = nil
        tia = nil
        efd = nil
        let service = DDTestMonitor.env.service
        
        guard let branchOrTag = (DDTestMonitor.env.git.branch ?? DDTestMonitor.env.git.tag),
              let commit = DDTestMonitor.env.git.commit?.sha else {
            Log.print("Unknown branch/tag and commit. Test Optimization can't be started")
            return
        }
        
        guard let repository = DDTestMonitor.env.git.repositoryURL?.spanAttribute else {
            Log.print("Unknown repository URL. Test Optimization can't be started")
            return
        }
        
        let getTracerConfig = { (log: String) in
            if let eventsExporter = DDTestMonitor.tracer.eventsExporter {
                return Log.measure(name: log) {
                    eventsExporter.tracerSettings(
                        service: service,
                        env: DDTestMonitor.env.environment,
                        repositoryURL: repository,
                        branch: branchOrTag,
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
        }
        testOptimizationSetupQueue.addOperation(updateTracerConfig)
        
        let automaticTestRetries = BlockOperation {
            guard let remote = tracerBackendConfig else {
                Log.print("ATR: error: backend config can't be loaded")
                return
            }
            guard AutomaticTestRetriesFactory.isEnabled(config: DDTestMonitor.config,
                                                        env: DDTestMonitor.env,
                                                        remote: remote)
            else {
                Log.print("ATR: disabled")
                return
            }
            self.atr = AutomaticTestRetriesFactory(config: DDTestMonitor.config).create(log: Log.instance)
        }
        automaticTestRetries.addDependency(updateTracerConfig)
        testOptimizationSetupQueue.addOperation(automaticTestRetries)
        
        let knownTestsSetup = BlockOperation {
            guard let remote = tracerBackendConfig else {
                Log.print("Known Tests: error: backend config can't be loaded")
                return
            }
            guard KnownTestsFactory.isEnabled(config: DDTestMonitor.config,
                                              env: DDTestMonitor.env,
                                              remote: remote)
            else {
                Log.print("Known Tests: disabled")
                return
            }
            guard let eventsExporter = DDTestMonitor.tracer.eventsExporter else {
                Log.print("Known Tests: init failed. Exporter is nil")
                return
            }
            guard let cache = try? DDTestMonitor.cacheManager?.session(feature: "known_tests") else {
                Log.print("Known Tests: init failed. Can't create cache directiry.")
                return
            }
            let factory = KnownTestsFactory(repository: repository, service: service,
                                            environment: DDTestMonitor.env.environment,
                                            configurations: DDTestMonitor.env.baseConfigurations,
                                            custom: DDTestMonitor.config.customConfigurations,
                                            exporter: eventsExporter, cache: cache)
            self.knownTests = factory.create(log: Log.instance)
        }
        knownTestsSetup.addDependency(updateTracerConfig)
        testOptimizationSetupQueue.addOperation(knownTestsSetup)
        
        let efdSetup = BlockOperation {
            guard let remote = tracerBackendConfig else {
                Log.print("EFD: error: backend config can't be loaded")
                return
            }
            guard EarlyFlakeDetectionFactory.isEnabled(config: DDTestMonitor.config, env: DDTestMonitor.env, remote: remote)
            else {
                Log.print("EFD: disabled")
                return
            }
            guard let knownTests = self.knownTests else {
                Log.print("EFD: init failed. Known Tests is nil")
                return
            }
            self.efd = EarlyFlakeDetectionFactory(knownTests: knownTests, settings: remote.efd).create(log: Log.instance)
        }
        efdSetup.addDependency(knownTestsSetup)
        testOptimizationSetupQueue.addOperation(efdSetup)
        
        let testManagementSetup = BlockOperation {
            guard let remote = tracerBackendConfig else {
                Log.print("Test Management: error: backend config can't be loaded")
                return
            }
            guard TestManagementFactory.isEnabled(config: DDTestMonitor.config,
                                                  env: DDTestMonitor.env,
                                                  remote: remote)
            else {
                Log.print("Test Management is disabled")
                return
            }
            guard let eventsExporter = DDTestMonitor.tracer.eventsExporter else {
                Log.print("Test Management: init failed. Exporter is nil")
                return
            }
            guard let cache = try? DDTestMonitor.cacheManager?.session(feature: "test_management") else {
                Log.print("Test Management: init failed. Can't create cache directiry.")
                return
            }
            let attemptToFixRetryCount = DDTestMonitor.config.testManagementAttemptToFixRetries ?? remote.testManagement.attemptToFixRetries
            guard let module = Bundle.testBundle?.name else {
                Log.print("Test Management: init failed. Can't determine test module")
                return
            }
            let sha = DDTestMonitor.env.git.commitHead?.sha ?? commit
            let message = DDTestMonitor.env.git.commitHead?.message ?? DDTestMonitor.env.git.commit?.message
            
            let factory = TestManagementFactory(repository: repository,
                                                commitSha: sha,
                                                commitMessage: message,
                                                module: module,
                                                attemptToFixRetries: attemptToFixRetryCount,
                                                exporter: eventsExporter,
                                                cache: cache)
            self.testManagement = factory.create(log: Log.instance)
        }
        testManagementSetup.addDependency(updateTracerConfig)
        testOptimizationSetupQueue.addOperation(testManagementSetup)
        
        let tiaSetup = BlockOperation { [self] in
            guard let remote = tracerBackendConfig else {
                Log.print("TIA: error: backend config can't be loaded")
                return
            }
            guard TestImpactAnalysisFactory.isEnabled(config: DDTestMonitor.config,
                                                      env: DDTestMonitor.env,
                                                      remote: remote)
            else {
                Log.print("TIA: disabled")
                return
            }
            guard let eventsExporter = DDTestMonitor.tracer.eventsExporter else {
                Log.print("TIA: init failed. Exporter is nil")
                return
            }
            guard let cache = try? DDTestMonitor.cacheManager?.session(feature: "tia") else {
                Log.print("TIA: init failed. Can't create cache directiry.")
                return
            }
            var coverage: TestImpactAnalysisFactory.Coverage? = nil
            if DDTestMonitor.config.codeCoverageEnabled && remote.itr.codeCoverage {
                guard let temp = try? DDTestMonitor.cacheManager?.temp(feature: "coverage") else {
                    Log.print("Code Coverage init failed. Can't create temp directory.")
                    return
                }
                coverage = .init(workspacePath: DDTestMonitor.env.workspacePath,
                                 priority: DDTestMonitor.config.codeCoveragePriority,
                                 tempFolder: temp,
                                 debug: DDTestMonitor.config.extraDebugCodeCoverage)
            }
            let factory = TestImpactAnalysisFactory(configurations: DDTestMonitor.env.baseConfigurations,
                                                    custom: DDTestMonitor.config.customConfigurations,
                                                    exporter: eventsExporter,
                                                    commit: commit,
                                                    repository: repository,
                                                    cache: cache,
                                                    skippingEnabled: remote.itr.testsSkipping,
                                                    coverage: coverage)
            self.tia = factory.create(log: Log.instance)
        }
        tiaSetup.addDependency(updateTracerConfig)
        testOptimizationSetupQueue.addOperation(tiaSetup)
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
    
    func loadSourceCodeInfo() {
#if targetEnvironment(simulator) || os(macOS)
        guard !DDTestMonitor.config.disableSourceLocation else {
            return
        }
        
        let testBundle = DDTestMonitor.config.isBinaryUnderUITesting ?
            Bundle.main : Bundle.testBundle
        
        if let bundleName = testBundle?.name {
            instrumentationWorkQueue.addOperation {
                Log.debug("Create test bundle DSYM file for test source location")
                Log.measure(name: "createDSYMFileIfNeeded") {
                    DDSymbolicator.createDSYMFileIfNeeded(forImageName: bundleName)
                }
                self.bundleFunctionInfo = Log.measure(name: "testFunctionsInModule") {
                    FileLocator.testFunctionsInModule(bundleName)
                }
            }
        }
            
        if let workspacePath = DDTestMonitor.env.workspacePath {
            instrumentationWorkQueue.addOperation {
                self.codeOwners = Log.measure(name: "createCodeOwners") {
                    CodeOwners(workspacePath: URL(fileURLWithPath: workspacePath, isDirectory: true))
                }
            }
        }
#endif
    }
    
    func setupCrashHandler() {
        DDTestMonitor.instance?.instrumentationWorkQueue.waitUntilAllOperationsAreFinished()
        // check if handler needed
        guard !DDTestMonitor.config.disableCrashHandler else {
            return
        }
        Log.measure(name: "Crash handler install") {
            DDCrashes.install(
                folder: try! DDTestMonitor.cacheManager!.session(feature: "crash"),
                disableMach: DDTestMonitor.config.disableMachCrashHandler
            )
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
    
    var activeFeatures: [any TestHooksFeature] {
        testOptimizationSetupQueue.waitUntilAllOperationsAreFinished()
        let features: [(any TestHooksFeature)?] = [
            testManagement, tia, efd, atr, knownTests,
            RetryAndSkipTags()
        ]
        return features.compactMap { $0 }
    }
}
