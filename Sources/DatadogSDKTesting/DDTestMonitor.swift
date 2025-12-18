/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

internal import EventsExporter
internal import OpenTelemetryApi
internal import OpenTelemetrySdk
internal import protocol EventsExporter.Logger

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

    //static var tracer = DDTracer()
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
    
    private let logger: Logger
    public let tracer: DDTracer
    private var api: TestOpmimizationApi
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
        let log = Log(env: DDTestMonitor.envReader)
        log.boostrap(config: DDTestMonitor.config)
        self.logger = log
    
        log.debug("Config:\n\(DDTestMonitor.config)")
        log.debug("Environment:\n\(DDTestMonitor.env)")
        log.debug("Session ID:\(DDTestMonitor.sessionId)")
        maxPayloadSize = DDTestMonitor.config.maxPayloadSize
        messageChannelUUID = DDTestMonitor.config.messageChannelUUID ?? UUID().uuidString
        
        // Create API
        let bundle = Bundle.main
        let identifier = bundle.bundleIdentifier ?? "com.datadoghq.DatadogSDKTesting"
        let version = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"

        let payloadCompression: Bool
        // When reporting tests to local server
        switch DDTestMonitor.config.endpoint {
        case let .other(testsBaseURL: tURL, logsBaseURL: _):
            payloadCompression = false
            Log.print("Reporting tests to \(tURL.absoluteURL)")
        default: payloadCompression = true
        }
        
        let clientId = String(SpanId.random().rawValue)

        let hostnameToReport: String? = (DDTestMonitor.config.reportHostname && !DDTestMonitor.developerMachineHostName.isEmpty) ? DDTestMonitor.developerMachineHostName : nil
        
        let apiConfig = APIServiceConfig(applicationName: identifier,
                                         version: version,
                                         device: .current,
                                         hostname: hostnameToReport,
                                         apiKey: DDTestMonitor.config.apiKey!,
                                         endpoint: DDTestMonitor.config.endpoint.exporterEndpoint,
                                         clientId: clientId,
                                         payloadCompression: payloadCompression)
        
        let httpClient = HTTPClient(debug: DDTestMonitor.config.extraDebugNetwork)
        
        let api = TestOpmimizationApiService(config: apiConfig, httpClient: httpClient, log: log)
        self.api = api
        
        let tracer = log.measure(name: "Tracer init") {
             DDTracer(config: DDTestMonitor.config,
                      environment: DDTestMonitor.env,
                      applicationId: identifier,
                      applicationVersion: version,
                      tracerVersion: DDTestMonitor.tracerVersion,
                      exporterId: clientId,
                      api: api, log: log)
        }
        self.tracer = tracer
        
        if DDTestMonitor.config.isBinaryUnderUITesting {
            launchNotificationObserver = NotificationCenter.default.addObserver(
                forName: launchNotificationName,
                object: nil, queue: nil)
            { _ in
                /// As crash reporter is initialized in testBundleWillStart() method, we initialize it here
                /// because dont have test observer
                self.setupCrashHandler()
                let launchedSpan = tracer.createSpanFromLaunchContext()
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
                        log.debug("DatadogTestingPort CFMessagePortCreateRemote failed")
                        return
                    }
                    guard let encoded = try? JSONSerialization.data(withJSONObject: data) else {
                        log.debug("Json encoding failed for: \(data)")
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
                        log.debug("DatadogTestingPort Success: \(data)")
                    } else {
                        log.debug("DatadogTestingPort Error: \(status)")
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
        tracer.flush()
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
        guard DDTestMonitor.env.isCI || GitUploader.statusUpToDate(workspace: workspace, log: logger) else {
            Log.print("Git status is not up to date")
            return
        }
        
        guard let commit = DDTestMonitor.env.git.commit?.sha, commit != "" else {
            Log.print("Commit SHA is empty. Git upload failed")
            self.isGitUploadSucceded = false
            return
        }
        
        let api = self.api
        let log = self.logger
        let config = DDTestMonitor.config
        
        guard config.gitUploadEnabled else {
            log.debug("Git Upload Disabled")
            self.isGitUploadSucceded = false
            return
        }
        
        gitUploadQueue.addOperation { [weak self] in
            self?.gitUploader = GitUploader(log: log,
                                            api: api.git,
                                            workspace: workspace,
                                            commitFolder: try? DDTestMonitor.cacheManager?.commit(feature: "git"))
            
            do {
                try self?.gitUploader?.sendGitInfo(repositoryURL: DDTestMonitor.env.git.repositoryURL,
                                                          commit: commit).await().get()
                self?.isGitUploadSucceded = true
            } catch {
                log.print("Git Upload failed: \(error)")
                self?.isGitUploadSucceded = false
            }
        }
    }

    func startTestOptimization() {
        var tracerBackendConfig: TracerSettings? = nil
        atr = nil
        tia = nil
        efd = nil
        let service = DDTestMonitor.env.service
        let api = self.api
        let logger = self.logger
        
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
            return logger.measure(name: log) {
                api.settings.tracerSettings(service: service,
                                            env: DDTestMonitor.env.environment,
                                            repositoryURL: repository,
                                            branch: branchOrTag,
                                            sha: commit,
                                            tiaLevel: .test,
                                            configurations: DDTestMonitor.env.baseConfigurations,
                                            customConfigurations: DDTestMonitor.config.customConfigurations).await()
            }
        }
        
        let updateTracerConfig = BlockOperation { [self] in
            switch getTracerConfig("Get Tracer Config") {
            case .failure(let err):
                logger.print("Failed to get tracer config: \(err)")
                tracerBackendConfig = nil
                return
            case .success(let config):
                tracerBackendConfig = config
                logger.debug("Tracer Config: \(config)")
            }
            guard tracerBackendConfig!.itr.requireGit else { return }
            logger.debug("ITR requires Git upload")
            gitUploadQueue.waitUntilAllOperationsAreFinished()
            guard isGitUploadSucceded else {
                Log.print("ITR requires Git but Git Upload failed. Disabling ITR")
                tracerBackendConfig!.itr.itrEnabled = false
                return
            }
            switch getTracerConfig("Get Tracer Config after git upload") {
            case .failure(let err):
                logger.print("Failed to get tracer config after git upload: \(err)")
            case .success(let config):
                tracerBackendConfig = config
                logger.debug("Tracer Config after git upload: \(config)")
            }
        }
        testOptimizationSetupQueue.addOperation(updateTracerConfig)
        
        let automaticTestRetries = BlockOperation {
            guard let remote = tracerBackendConfig else {
                logger.print("ATR: error: backend config can't be loaded")
                return
            }
            guard AutomaticTestRetriesFactory.isEnabled(config: DDTestMonitor.config,
                                                        env: DDTestMonitor.env,
                                                        remote: remote)
            else {
                logger.print("ATR: disabled")
                return
            }
            self.atr = try? AutomaticTestRetriesFactory(config: DDTestMonitor.config).create(log: logger).await().get()
        }
        automaticTestRetries.addDependency(updateTracerConfig)
        testOptimizationSetupQueue.addOperation(automaticTestRetries)
        
        let knownTestsSetup = BlockOperation {
            guard let remote = tracerBackendConfig else {
                logger.print("Known Tests: error: backend config can't be loaded")
                return
            }
            guard KnownTestsFactory.isEnabled(config: DDTestMonitor.config,
                                              env: DDTestMonitor.env,
                                              remote: remote)
            else {
                logger.print("Known Tests: disabled")
                return
            }
            guard let cache = try? DDTestMonitor.cacheManager?.session(feature: "known_tests") else {
                logger.print("Known Tests: init failed. Can't create cache directiry.")
                return
            }
            let factory = KnownTestsFactory(repository: repository, service: service,
                                            environment: DDTestMonitor.env.environment,
                                            configurations: DDTestMonitor.env.baseConfigurations,
                                            custom: DDTestMonitor.config.customConfigurations,
                                            api: api.knownTests, cache: cache)
            do {
                self.knownTests = try factory.create(log: Log.instance).await().get()
            } catch {
                self.knownTests = nil
                logger.print("Known Tests: init failed: \(error)")
            }
            
        }
        knownTestsSetup.addDependency(updateTracerConfig)
        testOptimizationSetupQueue.addOperation(knownTestsSetup)
        
        let efdSetup = BlockOperation {
            guard let remote = tracerBackendConfig else {
                logger.print("EFD: error: backend config can't be loaded")
                return
            }
            guard EarlyFlakeDetectionFactory.isEnabled(config: DDTestMonitor.config, env: DDTestMonitor.env, remote: remote)
            else {
                logger.print("EFD: disabled")
                return
            }
            guard let knownTests = self.knownTests else {
                logger.print("EFD: init failed. Known Tests is nil")
                return
            }
            self.efd = try? EarlyFlakeDetectionFactory(knownTests: knownTests, settings: remote.efd).create(log: logger).await().get()
        }
        efdSetup.addDependency(knownTestsSetup)
        testOptimizationSetupQueue.addOperation(efdSetup)
        
        let testManagementSetup = BlockOperation {
            guard let remote = tracerBackendConfig else {
                logger.print("Test Management: error: backend config can't be loaded")
                return
            }
            guard TestManagementFactory.isEnabled(config: DDTestMonitor.config,
                                                  env: DDTestMonitor.env,
                                                  remote: remote)
            else {
                logger.print("Test Management is disabled")
                return
            }
            guard let cache = try? DDTestMonitor.cacheManager?.session(feature: "test_management") else {
                logger.print("Test Management: init failed. Can't create cache directiry.")
                return
            }
            let attemptToFixRetryCount = DDTestMonitor.config.testManagementAttemptToFixRetries ?? remote.testManagement.attemptToFixRetries
            guard let module = Bundle.testBundle?.name else {
                logger.print("Test Management: init failed. Can't determine test module")
                return
            }
            let sha = DDTestMonitor.env.git.commitHead?.sha ?? commit
            let message = DDTestMonitor.env.git.commitHead?.message ?? DDTestMonitor.env.git.commit?.message
            let branch = DDTestMonitor.env.git.branch

            let factory = TestManagementFactory(repository: repository,
                                                commitSha: sha,
                                                commitMessage: message,
                                                branch: branch,
                                                module: module,
                                                attemptToFixRetries: attemptToFixRetryCount,
                                                api: api.testManagement,
                                                cache: cache)
            do {
                self.testManagement = try factory.create(log: logger).await().get()
            } catch {
                logger.print("Test Management: init failed: \(error)")
            }
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
                guard let exporter = self.tracer.eventsExporter?.coverageExporter else {
                    logger.print("Code Coverage init failed. Exporter is nil.")
                    return
                }
                coverage = .init(workspacePath: DDTestMonitor.env.workspacePath,
                                 priority: DDTestMonitor.config.codeCoveragePriority,
                                 tempFolder: temp,
                                 debug: DDTestMonitor.config.extraDebugCodeCoverage,
                                 exporter: exporter)
            }
            let factory = TestImpactAnalysisFactory(configurations: DDTestMonitor.env.baseConfigurations,
                                                    custom: DDTestMonitor.config.customConfigurations,
                                                    api: api.tia,
                                                    commit: commit,
                                                    repository: repository,
                                                    environment: DDTestMonitor.env.environment,
                                                    service: DDTestMonitor.env.service,
                                                    cache: cache,
                                                    skippingEnabled: remote.itr.testsSkipping,
                                                    coverage: coverage)
            do {
                self.tia = try factory.create(log: logger).await().get()
            } catch {
                logger.print("TIA: init failed: \(error)")
            }
        }
        tiaSetup.addDependency(updateTracerConfig)
        testOptimizationSetupQueue.addOperation(tiaSetup)
    }

    func startInstrumenting() {
        guard !DDTestMonitor.config.disableTestInstrumenting else {
            return
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
                disableMach: DDTestMonitor.config.disableMachCrashHandler,
                tracer: self.tracer
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
