/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

#if canImport(UIKit)
    import UIKit
    let launchNotificationName = UIApplication.didFinishLaunchingNotification
    let didBecomeActiveNotificationName = UIApplication.didBecomeActiveNotification
#elseif canImport(Cocoa)
    import Cocoa
    let launchNotificationName = NSApplication.didFinishLaunchingNotification
    let didBecomeActiveNotificationName = NSApplication.didBecomeActiveNotification
#endif

internal class DDTestMonitor {
    static var instance: DDTestMonitor?

    static let defaultPayloadSize = 1024

    static var tracer = DDTracer()
    static var env = DDEnvironmentValues()

    var networkInstrumentation: DDNetworkInstrumentation?
    var injectHeaders: Bool = false
    var recordPayload: Bool = false
    var maxPayloadSize: Int = defaultPayloadSize
    var launchNotificationObserver: NSObjectProtocol?
    var didBecomeActiveNotificationObserver: NSObjectProtocol?

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

    static func installTestMonitor() {
        guard DDEnvironmentValues.getEnvVariable("DATADOG_CLIENT_TOKEN") != nil || DDEnvironmentValues.getEnvVariable("DD_API_KEY") != nil else {
            Log.print("DATADOG_CLIENT_TOKEN or DD_API_KEY are missing.")
            return
        }
        if DDEnvironmentValues.getEnvVariable("SRCROOT") == nil {
            Log.print("SRCROOT is not properly set")
        }
        Log.print("Library loaded and active. Instrumenting tests.")
        DDTestMonitor.instance = DDTestMonitor()
        DDTestMonitor.instance?.startInstrumenting()
    }

    init() {
        if DDTestMonitor.tracer.isBinaryUnderUITesting {
            /// If the library is being loaded in a binary launched from a UITest, dont start test observing,
            /// except if testing the tracer itself
            launchNotificationObserver = NotificationCenter.default.addObserver(
                forName: launchNotificationName,
                object: nil, queue: nil) { _ in
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
                    object: nil, queue: nil) { _ in
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
                                                              0x1111, // Arbitrary
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

    func startInstrumenting() {
        guard !DDTestMonitor.env.disableTestInstrumenting else {
            return
        }

        if !DDTestMonitor.env.disableNetworkInstrumentation {
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
        if DDTestMonitor.env.enableStdoutInstrumentation {
            startStdoutCapture()
        }
        if DDTestMonitor.env.enableStderrInstrumentation {
            startStderrCapture()
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
        #if targetEnvironment(simulator) || os(macOS)
            func attributeCallback(port: CFMessagePort?, msgid: Int32, data: CFData?, info: UnsafeMutableRawPointer?) -> Unmanaged<CFData>? {
                if let data = data as Data? {
                    let decoded = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                    decoded?.forEach {
                        DDTestMonitor.instance?.currentTest?.setTag(key: $0.key, value: $0.value)
                    }
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
        #endif
    }
}
