/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

@_implementationOnly import DatadogExporter
#if canImport(UIKit)
import UIKit
let launchNotificationName = UIApplication.didFinishLaunchingNotification
#elseif canImport(Cocoa)
import Cocoa
let launchNotificationName = NSApplication.didFinishLaunchingNotification
#endif

internal class DDTestMonitor {
    static var instance: DDTestMonitor?

    static let defaultPayloadSize = 1024

    static var tracer = DDTracer()
    static var env = DDEnvironmentValues()

    var networkInstrumentation: DDNetworkInstrumentation?
    var stderrCapturer: StderrCapture
    var injectHeaders: Bool = false
    var recordPayload: Bool = false
    var maxPayloadSize: Int = defaultPayloadSize
    var notificationObserver: NSObjectProtocol?

    private var lock = os_unfair_lock_s()
    private var privateCurrentTest: DDTest?
    var currentTest: DDTest? {
        get {
            os_unfair_lock_lock(&lock)
            defer { os_unfair_lock_unlock(&lock) }
            return privateCurrentTest
        }
        set {
            os_unfair_lock_lock(&lock)
            defer { os_unfair_lock_unlock(&lock) }
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
        stderrCapturer = StderrCapture()
        if DDTestMonitor.tracer.isBinaryUnderUITesting {
            /// If the library is being loaded in a binary launched from a UITest, dont start test observing,
            /// except if testing the tracer itself
            notificationObserver = NotificationCenter.default.addObserver(
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
        if !DDTestMonitor.env.disableStdoutInstrumentation {
            startStdoutCapture()
        }
        if !DDTestMonitor.env.disableStderrInstrumentation {
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
        StdoutCapture.startCapturing(tracer: DDTestMonitor.tracer)
    }

    func stopStdoutCapture() {
        StdoutCapture.stopCapturing()
    }

    func startStderrCapture() {
        stderrCapturer.startCapturing(tracer: DDTestMonitor.tracer)
    }

    func stopStderrCapture() {
        stderrCapturer.stopCapturing()
    }
}
