/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

@_implementationOnly import EventsExporter
@_implementationOnly import OpenTelemetryApi

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
    static var clock = NTPClock()

    static let defaultPayloadSize = 1024

    static var tracer = DDTracer()
    static var env = DDEnvironmentValues()

    var networkInstrumentation: DDNetworkInstrumentation?
    var injectHeaders: Bool = false
    var recordPayload: Bool = false
    var maxPayloadSize: Int = defaultPayloadSize
    var launchNotificationObserver: NSObjectProtocol?
    var didBecomeActiveNotificationObserver: NSObjectProtocol?
    var isRumActive: Bool = false

    var crashedModuleInfo: CrashedModuleInformation?

    let instrumentationWorkQueue = OperationQueue()
    let itrWorkQueue = OperationQueue()

    static let developerMachineHostName: String = Spawn.commandWithResult("hostname").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

    static var baseConfigurationTags = [
        DDOSTags.osPlatform: env.osName,
        DDOSTags.osArchitecture: env.osArchitecture,
        DDOSTags.osVersion: env.osVersion,
        DDDeviceTags.deviceModel: env.deviceModel,
        DDRuntimeTags.runtimeName: env.runtimeName,
        DDRuntimeTags.runtimeVersion: env.runtimeVersion,
        DDUISettingsTags.uiSettingsLocalization: PlatformUtils.getLocalization(),
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

    static var localRepositoryURLPath: String {
        guard let workspacePath = DDTestMonitor.env.workspacePath else {
            return ""
        }
        let url = Spawn.commandWithResult(#"git -C "\#(workspacePath)" config --get remote.origin.url"#).trimmingCharacters(in: .whitespacesAndNewlines)
        return url
    }

    static func installTestMonitor() -> Bool {
        guard DDEnvironmentValues.getEnvVariable(ConfigurationValues.DD_API_KEY.rawValue) != nil else {
            Log.print("A Datadog API key is required. DD_API_KEY environment value is missing.")
            return false
        }
        if DDEnvironmentValues.getEnvVariable(ConfigurationValues.SRCROOT.rawValue) == nil {
            Log.print("SRCROOT is not properly set")
        }
        Log.print("Library loaded and active. Instrumenting tests.")
        DDTestMonitor.instance = DDTestMonitor()
        Log.measure(name: "startInstrumenting") {
            DDTestMonitor.instance?.startInstrumenting()
        }

        Log.measure(name: "startITR") {
            DDTestMonitor.instance?.startITR()
        }
        return true
    }

    init() {
        let isBinaryUnderTesting = DDEnvironmentValues.getEnvVariable("ENVIRONMENT_TRACER_TRACEID") != nil &&
            DDEnvironmentValues.getEnvVariable("ENVIRONMENT_TRACER_SPANID") != nil

        if isBinaryUnderTesting {
            launchNotificationObserver = NotificationCenter.default.addObserver(
                forName: launchNotificationName,
                object: nil, queue: nil)
            { _ in
                /// As crash reporter is initialized in testBundleWillStart() method, we initialize it here
                /// because dont have test observer
                if !DDTestMonitor.env.disableCrashHandler {
                    DDCrashes.install()
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
                    let encoded = try? JSONSerialization.data(withJSONObject: data)
                    let timeout: CFTimeInterval = 1.0
                    let remotePort = CFMessagePortCreateRemote(nil, "DatadogTestingPort" as CFString)
                    if remotePort == nil {
                        Log.debug("DatadogTestingPort CFMessagePortCreateRemote failed")
                        return
                    }
                    let status = CFMessagePortSendRequest(remotePort,
                                                          DDCFMessageID.setCustomTags,
                                                          encoded as CFData?,
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

    func startITR() {
        if DDTestMonitor.env.ddApplicationKey == nil {
            Log.print("APPLICATION_KEY env variable is not set, this is only needed if you use Intelligent Test Runner")
            return
        }

        /// Check Git is up to date and no local changes
        guard DDTestMonitor.env.isCi || GitUploader.statusUpToDate() else {
            Log.debug("Git status not up to date")
            coverageHelper = nil
            itr = nil
            return
        }
        
        instrumentationWorkQueue.waitUntilAllOperationsAreFinished()
        
        itrWorkQueue.addOperation { [self] in
            if DDTestMonitor.env.gitUploadEnabled {
                Log.debug("Git Upload Enabled")
                gitUploader = try? GitUploader()
            } else {
                Log.debug("Git Upload Disabled")
            }
            gitUploader?.sendGitInfo()
        }

        var itrBackendConfig: (codeCoverage: Bool, testsSkipping: Bool)?

        itrWorkQueue.addOperation {
            if let service = DDTestMonitor.env.ddService ?? DDTestMonitor.env.getRepositoryName(),
               let branch = DDTestMonitor.env.branch,
               let commit = DDTestMonitor.env.commit,
               let eventsExporter = DDTestMonitor.tracer.eventsExporter
            {
                let ddEnvironment = DDTestMonitor.env.ddEnvironment ?? (DDTestMonitor.env.isCi ? "ci" : "none")

                Log.measure(name: "itrBackendConfig") {
                    itrBackendConfig = eventsExporter.itrSetting(service: service,
                                                                 env: ddEnvironment,
                                                                 repositoryURL: DDTestMonitor.localRepositoryURLPath,
                                                                 branch: branch,
                                                                 sha: commit,
                                                                 configurations: DDTestMonitor.baseConfigurationTags,
                                                                 customConfigurations: DDTestMonitor.env.customConfigurations)
                }
            } else {
                itrBackendConfig = nil
            }
        }

        itrWorkQueue.waitUntilAllOperationsAreFinished()

        itrWorkQueue.addOperation { [self] in

            /// Check branch is not excluded
            if let excludedBranches = DDTestMonitor.env.excludedBranches,
               let currentBranch = DDTestMonitor.env.branch
            {
                if excludedBranches.contains(currentBranch) {
                    Log.debug("Excluded branch: \(currentBranch)")
                    itr = nil
                    return
                }
                let wildcardBranches = excludedBranches.filter { $0.hasSuffix("*") }.map { $0.dropLast() }
                for branch in wildcardBranches {
                    if currentBranch.hasPrefix(branch) {
                        Log.debug("Excluded branch with wildcard: \(currentBranch)")
                        itr = nil
                        return
                    }
                }
            }

            // Activate Intelligent Test Runner
            if DDTestMonitor.env.itrEnabled ?? itrBackendConfig?.testsSkipping ?? false {
                Log.debug("ITR Enabled")
                itr = IntelligentTestRunner(configurations: DDTestMonitor.baseConfigurationTags)
                itr?.start()
            } else {
                Log.debug("ITR Disabled")
                itr = nil
            }
        }

        itrWorkQueue.addOperation { [self] in
            // Activate Coverage
            if DDTestMonitor.env.coverageEnabled ?? itrBackendConfig?.codeCoverage ?? false {
                Log.debug("Coverage Enabled")
                // Coverage is not supported for swift < 5.3 (binary target dependency)
                #if swift(>=5.3)
                    coverageHelper = DDCoverageHelper()
                #else
                    coverageHelper = nil
                #endif

            } else {
                Log.debug("Coverage Disabled")
                coverageHelper = nil
            }
        }
    }

    func startInstrumenting() {
        guard !DDTestMonitor.env.disableTestInstrumenting else {
            return
        }

        if !DDTestMonitor.env.disableNetworkInstrumentation {
            instrumentationWorkQueue.addOperation { [self] in
                Log.measure(name: "DDTracer") {
                    _ = DDTestMonitor.tracer
                }
                Log.measure(name: "startNetworkAutoInstrumentation") {
                    startNetworkAutoInstrumentation()
                    if !DDTestMonitor.env.disableHeadersInjection {
                        injectHeaders = true
                    }
                    if DDTestMonitor.env.enableRecordPayload {
                        recordPayload = true
                    }
                    if let maxPayload = DDTestMonitor.env.maxPayloadSize {
                        maxPayloadSize = maxPayload
                    }
                }
            }
        }
        if DDTestMonitor.env.enableStdoutInstrumentation {
            instrumentationWorkQueue.addOperation { [self] in
                Log.measure(name: "startStdoutCapture") {
                    startStdoutCapture()
                }
            }
        }
        if DDTestMonitor.env.enableStderrInstrumentation {
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

    func startAttributeListener() {
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

        let port = CFMessagePortCreateLocal(nil, "DatadogTestingPort" as CFString, attributeCallback, nil, nil)
        if port == nil {
            Log.debug("DatadogTestingPort CFMessagePortCreateLocal failed")
            return
        }
        let runLoopSource = CFMessagePortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, CFRunLoopMode.commonModes)
    }
}
