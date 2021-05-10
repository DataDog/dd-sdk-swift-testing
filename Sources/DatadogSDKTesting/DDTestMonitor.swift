/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import DatadogExporter
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

    let tracer: DDTracer
    var testObserver: DDTestObserver?
    var networkInstrumentation: DDNetworkInstrumentation?
    var stderrCapturer: StderrCapture
    var injectHeaders: Bool = false
    var recordPayload: Bool = false
    var maxPayloadSize: Int = defaultPayloadSize
    var notificationObserver: NSObjectProtocol?

    init() {
        tracer = DDTracer()
        stderrCapturer = StderrCapture()
        /// If the library is being loaded in a binary launched from a UITest, dont start test observing
        if !tracer.isBinaryUnderUITesting {
            testObserver = DDTestObserver(tracer: tracer)
        } else {
            notificationObserver = NotificationCenter.default.addObserver(
                forName: launchNotificationName,
                object: nil, queue: nil) { [weak self] _ in
                    /// As crash reporter is initialized in testBundleWillStart() method, we initialize it here
                    /// because dont have test observer
                    guard let self = self else {
                        return
                    }
                    if !self.tracer.env.disableCrashHandler {
                        DDCrashes.install()
                        let launchedSpan = self.tracer.createSpanFromLaunchContext()
                        let simpleSpan = SimpleSpanData(spanData: launchedSpan.toSpanData())
                        DDCrashes.setCustomData(customData: SimpleSpanSerializer.serializeSpan(simpleSpan: simpleSpan))
                    }
            }
        }
    }

    func startInstrumenting() {
        testObserver?.startObserving()
        if !tracer.env.disableNetworkInstrumentation {
            startNetworkAutoInstrumentation()
            if !tracer.env.disableHeadersInjection {
                injectHeaders = true
            }
            if tracer.env.enableRecordPayload {
                recordPayload = true
            }
            if let maxPayload = tracer.env.maxPayloadSize {
                maxPayloadSize = maxPayload
            }
        }
        if !tracer.env.disableStdoutInstrumentation {
            startStdoutCapture()
        }
        if !tracer.env.disableStderrInstrumentation {
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
        StdoutCapture.startCapturing(tracer: tracer)
    }

    func stopStdoutCapture() {
        StdoutCapture.stopCapturing()
    }

    func startStderrCapture() {
        stderrCapturer.startCapturing(tracer: tracer)
    }

    func stopStderrCapture() {
        stderrCapturer.stopCapturing()
    }
}
